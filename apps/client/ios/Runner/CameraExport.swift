import AVFoundation

/// Builds the soundtrack from the verified native transport timeline and source
/// assets. Output is reconstructed source audio, with every transport gap retained.
enum CameraExport {
    struct Result {
        let duration: Double
        let size: CGSize
        let audioSegments: Int
    }

    static func save(video: URL, segments: [CameraAudioSegment], sources: [String: URL],
                     videoStart: Double, restoreTempo: Bool, to destination: URL) async throws -> Result {
        var stage = "reading the camera video"
        do {
            let movie = AVURLAsset(url: video)
            defer { withExtendedLifetime(movie) {} }
            guard let original = try await movie.loadTracks(withMediaType: .video).first else {
                throw CameraExportError("The camera file has no video track. Your original file is kept.")
            }
            let range = try await original.load(.timeRange)
            let clipped = try CameraTimeline.clip(segments, videoStart: videoStart, duration: range.duration.seconds)
            let duration = CameraTimeline.duration(clipped, restoreTempo: restoreTempo)
            let composition = AVMutableComposition()
            guard let picture = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CameraExportError("The video exporter is unavailable.")
            }
            try picture.insertTimeRange(range, of: original, at: .zero)
            picture.preferredTransform = try await original.load(.preferredTransform)
            let size = try await original.load(.naturalSize)
            if restoreTempo {
                for segment in clipped.reversed() where segment.sourceKey != nil && abs(segment.rate - 1) > 0.000001 {
                    let wall = segment.hostEnd - segment.hostStart
                    picture.scaleTimeRange(CMTimeRange(start: time(segment.hostStart - videoStart), duration: time(wall)),
                                           toDuration: time(wall * segment.rate))
                }
            }

            let working = FileManager.default.temporaryDirectory.appendingPathComponent("hyperstream-export-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: working) }
            let sound = working.appendingPathComponent("soundtrack.m4a")
            stage = "building the soundtrack"
            try await soundtrack(clipped, sources: sources, restoreTempo: restoreTempo,
                                 duration: duration, working: working, to: sound)
            stage = "adding the encoded soundtrack"
            let encoded = AVURLAsset(url: sound)
            defer { withExtendedLifetime(encoded) {} }
            guard let audio = try await encoded.loadTracks(withMediaType: .audio).first,
                  let output = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CameraExportError("The soundtrack could not be added to the video.")
            }
            let audioRange = try await audio.load(.timeRange)
            let length = CMTimeMinimum(time(duration), audioRange.duration)
            try output.insertTimeRange(CMTimeRange(start: audioRange.start, duration: length), of: audio, at: .zero)
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality),
                  export.supportedFileTypes.contains(.mp4) else {
                throw CameraExportError("The video export format is unavailable.")
            }
            export.audioTimePitchAlgorithm = .timeDomain
            let note = AVMutableMetadataItem()
            note.identifier = .identifier3GPUserDataDescription
            note.extendedLanguageTag = "en"
            note.value = (restoreTempo ? "Hyperstream. Source soundtrack at original tempo." :
                            "Hyperstream. Source soundtrack following recorded playback timing.") as NSString
            note.dataType = kCMMetadataBaseDataType_UTF8 as String
            export.metadata = [note]
            let ready = working.appendingPathComponent("ready.mp4")
            stage = "encoding the finished video"
            try await finish(export, to: ready, type: .mp4)
            // A completed movie is published atomically. An existing destination is never replaced.
            stage = "publishing the finished video"
            try FileManager.default.moveItem(at: ready, to: destination)
            return Result(duration: duration, size: size,
                          audioSegments: clipped.filter { $0.sourceKey != nil }.count)
        } catch { throw failure(stage, error: error) }
    }

    private static func soundtrack(_ segments: [CameraAudioSegment], sources: [String: URL], restoreTempo: Bool,
                                   duration: Double, working: URL, to destination: URL) async throws {
        var stage = "preparing soundtrack silence"
        do {
            let composition = AVMutableComposition()
            guard let baseline = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid),
                  let preservedMusic = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid),
                  let shiftedMusic = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CameraExportError("The soundtrack exporter is unavailable.")
            }
            // An explicit baseline preserves leading, trailing and all-paused takes.
            let silence = working.appendingPathComponent("silence.caf")
            try writeSilence(duration: duration, to: silence)
            let silenceAsset = AVURLAsset(url: silence)
            defer { withExtendedLifetime(silenceAsset) {} }
            guard let silentTrack = try await silenceAsset.loadTracks(withMediaType: .audio).first else {
                throw CameraExportError("The silent portions of the take could not be prepared.")
            }
            try baseline.insertTimeRange(CMTimeRange(start: .zero, duration: time(duration)), of: silentTrack, at: .zero)
            var cursor = 0.0
            var tracks: [String: AVAssetTrack] = [:]
            // AVAssetTrack.asset is weak. Retain every source through composition
            // insertion and rendering, including across asynchronous track loads.
            var sourceAssets: [String: AVURLAsset] = [:]
            defer { withExtendedLifetime(sourceAssets) {} }
            for segment in segments {
                let wall = segment.hostEnd - segment.hostStart
                let length = wall * (restoreTempo && segment.sourceKey != nil ? segment.rate : 1)
                defer { cursor += length }
                guard let key = segment.sourceKey else { continue }
                if tracks[key] == nil {
                    guard let url = sources[key], url.isFileURL else {
                        throw CameraExportError("A song needed for this take is unavailable. Keep the take and retry.")
                    }
                    stage = "reading a source song"
                    // Playback accepts more formats than AVAsset composition.
                    // Cached takes deliberately have opaque .audio filenames;
                    // recover the container from its bytes, including old takes.
                    let prepared = try await readableSource(url, in: working)
                    let asset = AVURLAsset(url: prepared)
                    sourceAssets[key] = asset
                    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                        throw CameraExportError("A song needed for this take has no audio track. Keep the take and retry.")
                    }
                    tracks[key] = track
                }
                guard let track = tracks[key] else { continue }
                stage = "checking a source song interval"
                let available = try await track.load(.timeRange)
                let start = segment.sourceStart
                let end = start + wall * segment.rate
                guard start >= available.start.seconds - 0.001,
                      end <= available.end.seconds + 0.075 else {
                    throw CameraExportError("A song does not cover its recorded interval. Your original video is kept.")
                }
                let clippedStart = max(start, available.start.seconds)
                let clippedEnd = min(end, available.end.seconds)
                // Native MP3 duration can differ from the downloaded track by a
                // codec frame. Preserve the requested rate and the video timeline,
                // leaving that short unavailable tail on the silent baseline.
                guard clippedEnd > clippedStart else { continue }
                let sourceRange = CMTimeRange(start: time(clippedStart), duration: time(clippedEnd - clippedStart))
                let playbackRate = restoreTempo ? 1 : segment.rate
                let audibleStart = cursor + (clippedStart - start) / playbackRate
                let audibleDuration = (clippedEnd - clippedStart) / playbackRate
                stage = "inserting a source song interval"
                // The algorithm applies to an entire composition track. Keep
                // modes on separate tracks so a toggle during a take survives.
                let music = restoreTempo || segment.preservesPitch ? preservedMusic : shiftedMusic
                try music.insertTimeRange(sourceRange, of: track, at: time(audibleStart))
                music.scaleTimeRange(CMTimeRange(start: time(audibleStart), duration: sourceRange.duration),
                                     toDuration: time(audibleDuration))
            }
            let preserved = AVMutableAudioMixInputParameters(track: preservedMusic)
            preserved.audioTimePitchAlgorithm = .spectral
            let shifted = AVMutableAudioMixInputParameters(track: shiftedMusic)
            shifted.audioTimePitchAlgorithm = .varispeed
            let mix = AVMutableAudioMix()
            mix.inputParameters = [preserved, shifted]
            stage = "encoding the AAC soundtrack"
            try await encodeAudio(composition, mix: mix, duration: duration, to: destination)
        } catch { throw failure(stage, error: error) }
    }

    private static func readableSource(_ url: URL, in working: URL) async throws -> URL {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = [UInt8](try handle.read(upToCount: 16) ?? Data())
        func starts(_ text: String) -> Bool { bytes.starts(with: Array(text.utf8)) }
        let type: String?
        if starts("fLaC") { type = "flac" }
        else if starts("caff") { type = "caf" }
        else if starts("RIFF") { type = "wav" }
        else if starts("FORM") { type = "aiff" }
        else if bytes.count >= 8, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" { type = "m4a" }
        else if starts("ID3") { type = "mp3" }
        else if bytes.count >= 2, bytes[0] == 0xff, bytes[1] & 0xf6 == 0xf0 { type = "aac" }
        else if bytes.count >= 2, bytes[0] == 0xff, bytes[1] & 0xe0 == 0xe0 { type = "mp3" }
        else { type = nil }
        var input = url
        if let type, url.pathExtension.lowercased() != type {
            input = working.appendingPathComponent(UUID().uuidString + "." + type)
            // Link within the app's container where possible; copying is safe on
            // filesystems that cannot link. Never modify the retained original.
            do { try FileManager.default.linkItem(at: url, to: input) }
            catch { try FileManager.default.copyItem(at: url, to: input) }
        }
        if type != "flac" {
            let asset = AVURLAsset(url: input)
            if let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty {
                return input
            }
        }
        // Core Audio can decode FLAC that AVURLAsset cannot compose. A temporary
        // PCM CAF preserves sample rate, channels and timing without a lossy
        // intermediate encode. Chunked decoding keeps long mixes out of RAM.
        let file = try AVAudioFile(forReading: input)
        let format = file.processingFormat
        guard file.length > 0, format.sampleRate.isFinite, format.sampleRate > 0,
              format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
            throw CameraExportError("The source song could not be decoded. Your original take is kept.")
        }
        let output = working.appendingPathComponent(UUID().uuidString + ".caf")
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        // This scope releases the writer (and finalizes its header) before load.
        do {
            let writer = try AVAudioFile(forWriting: output, settings: settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else {
                    throw CameraExportError("The source song ended before it could be decoded. Your original take is kept.")
                }
                try writer.write(from: buffer)
            }
        }
        return output
    }

    private static func writeSilence(duration: Double, to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let channels = buffer.floatChannelData else {
            throw CameraExportError("The soundtrack buffer is unavailable.")
        }
        for channel in 0..<2 { memset(channels[channel], 0, 4096 * MemoryLayout<Float>.size) }
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings)
        var remaining = Int64((duration * 48_000).rounded(.up))
        while remaining > 0 {
            buffer.frameLength = UInt32(min(4096, remaining))
            try file.write(from: buffer)
            remaining -= Int64(buffer.frameLength)
        }
    }

    private static func encodeAudio(_ asset: AVComposition, mix: AVAudioMix, duration: Double,
                                    to url: URL) async throws {
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix
        output.audioTimePitchAlgorithm = .timeDomain
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000,
        ])
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(output), writer.canAdd(input) else {
            throw CameraExportError("The AAC soundtrack encoder is unavailable.")
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: time(duration))
        writer.add(input)
        guard writer.startWriting() else { throw failure("starting the AAC writer", error: writer.error) }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw failure("starting the soundtrack reader", error: reader.error)
        }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "hyperstream.camera.audio-export")
            var finished = false
            input.requestMediaDataWhenReady(on: queue) {
                guard !finished else { return }
                if writer.status == .failed || writer.status == .cancelled {
                    finished = true
                    reader.cancelReading()
                    done.resume(throwing: failure("feeding the AAC writer", error: writer.error))
                    return
                }
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        finished = true
                        input.markAsFinished()
                        if reader.status == .failed || reader.status == .cancelled {
                            writer.cancelWriting()
                            done.resume(throwing: failure("decoding the soundtrack mix", error: reader.error))
                        } else {
                            writer.endSession(atSourceTime: time(duration))
                            writer.finishWriting {
                                if writer.status == .completed { done.resume() }
                                else { done.resume(throwing: failure("finishing the AAC writer", error: writer.error)) }
                            }
                        }
                        return
                    }
                    guard input.append(sample) else {
                        finished = true
                        reader.cancelReading()
                        writer.cancelWriting()
                        done.resume(throwing: failure("appending soundtrack samples", error: writer.error))
                        return
                    }
                }
            }
        }
    }

    private static func finish(_ export: AVAssetExportSession, to url: URL, type: AVFileType) async throws {
        export.outputURL = url
        export.outputFileType = type
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            export.exportAsynchronously {
                if export.status == .completed { done.resume() }
                else { done.resume(throwing: failure("encoding the finished video", error: export.error)) }
            }
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    private static func failure(_ stage: String, error: Error?) -> CameraExportError {
        if let known = error as? CameraExportError { return known }
        var codes: [String] = []
        var current = error.map { $0 as NSError }
        while let value = current, codes.count < 3 {
            codes.append("\(value.domain) \(value.code)")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let detail = codes.isEmpty ? "" : " (" + codes.joined(separator: ", ") + ")"
        return CameraExportError("Could not finish \(stage)\(detail). Your original take is kept.")
    }
}
