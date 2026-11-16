import AVFoundation
import Foundation

/// Compiles with the production timeline/export files on the Apple CI runner.
@main
struct CameraExportCheck {
    static func main() async throws {
        try await playbackClock()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hyperstream-camera-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("camera.mov")
        let songA = root.appendingPathComponent("a.caf")
        let songB = root.appendingPathComponent("b.caf")
        try tone(to: songA, base: 220, step: 110)
        try tone(to: songB, base: 300, step: 100)
        try await video(to: raw)
        let segments = [
            CameraAudioSegment(hostStart: 99.5, hostEnd: 102, sourceKey: "a", sourceStart: 1, rate: 0.75),
            CameraAudioSegment(hostStart: 102.5, hostEnd: 104, sourceKey: "a", sourceStart: 5, rate: 1.5),
            CameraAudioSegment(hostStart: 104, hostEnd: 105.5, sourceKey: "b", sourceStart: 1),
        ]
        let clipped = try CameraTimeline.clip(segments, videoStart: 100, duration: 6)
        precondition(clipped.count == 5, "Pause and trailing silence must be explicit")
        precondition(abs(clipped[0].sourceStart - 1.375) < 0.000001, "A clipped head advances source time at playback rate")
        precondition(clipped[1].sourceKey == nil && clipped[4].sourceKey == nil)
        precondition(abs(CameraTimeline.duration(clipped, restoreTempo: false) - 6) < 0.000001)
        precondition(abs(CameraTimeline.duration(clipped, restoreTempo: true) - 6.25) < 0.000001)
        let encoded = try JSONEncoder().encode(segments)
        let decoded = try JSONDecoder().decode([CameraAudioSegment].self, from: encoded)
        precondition(decoded == segments)
        try timelineFailures()

        for original in [false, true] {
            let target = root.appendingPathComponent(original ? "original.mp4" : "performance.mp4")
            let result = try await CameraExport.save(video: raw, segments: segments, sources: ["a": songA, "b": songB],
                                                     videoStart: 100, restoreTempo: original, to: target)
            let expected = original ? 6.25 : 6.0
            precondition(abs(result.duration - expected) < 0.001 && result.audioSegments == 3)
            let asset = AVURLAsset(url: target)
            let duration = try await asset.load(.duration).seconds
            precondition(abs(duration - expected) < 0.06, "Export duration \(duration) differs from \(expected)")
            let track = try await asset.loadTracks(withMediaType: .video).first!
            let dimensions = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let display = CGRect(origin: .zero, size: dimensions).applying(transform)
            precondition(abs(display.height) > abs(display.width), "Portrait orientation must survive export")
            let samples = try await decode(target)
            try assertTone(samples, at: 0.2, frequency: 330)
            try assertTone(samples, at: original ? 2.2 : 2.7, frequency: 770)
            try assertTone(samples, at: original ? 4.6 : 4.35, frequency: 400)
            precondition(rms(samples, at: original ? 1.65 : 2.15) < 0.002, "Paused audio must stay silent")
            precondition(rms(samples, at: original ? 5.9 : 5.65) < 0.002, "Trailing pause must stay silent")
        }
        let silent = root.appendingPathComponent("paused.mp4")
        _ = try await CameraExport.save(video: raw, segments: [], sources: [:], videoStart: 100,
                                        restoreTempo: true, to: silent)
        let silentSamples = try await decode(silent)
        precondition(rms(silentSamples, at: 1) < 0.00001)
        let tailSegments = [CameraAudioSegment(hostStart: 100, hostEnd: 102.73,
                                              sourceKey: "a", sourceStart: 8, rate: 0.75)]
        for original in [false, true] {
            let target = root.appendingPathComponent(original ? "tail-original.mp4" : "tail-performance.mp4")
            let result = try await CameraExport.save(video: raw, segments: tailSegments, sources: ["a": songA],
                                                     videoStart: 100, restoreTempo: original, to: target)
            let expected = original ? 5.3175 : 6
            precondition(abs(result.duration - expected) < 0.001)
            let samples = try await decode(target)
            try assertTone(samples, at: 0.2, frequency: 1100)
            precondition(rms(samples, at: original ? 2.035 : 2.71, frames: 240) < 0.003,
                         "A rounded source tail must stay silent without stretching music")
        }
        do {
            let tooLong = [CameraAudioSegment(hostStart: 100, hostEnd: 103, sourceKey: "a", sourceStart: 8, rate: 0.75)]
            _ = try await CameraExport.save(video: raw, segments: tooLong, sources: ["a": songA], videoStart: 100,
                                            restoreTempo: false, to: root.appendingPathComponent("overrun.mp4"))
            preconditionFailure("A material source mismatch must remain a recoverable failure")
        } catch is CameraExportError {}
        do {
            _ = try await CameraExport.save(video: raw, segments: segments, sources: [:], videoStart: 100,
                                            restoreTempo: false, to: root.appendingPathComponent("missing.mp4"))
            preconditionFailure("An unavailable source must remain a recoverable export failure")
        } catch is CameraExportError {}
        print("Camera export passed clipping, Codable retry, overlap rejection, 0.75×/1.5× source timing, seek, queue change, pauses, source-tail rounding, pitch, portrait orientation, 48 kHz AAC and both tempo modes.")
    }

    private static func playbackClock() async throws {
        var parent: CMTimebase?
        var child: CMTimebase?
        let host = CMClockGetHostTimeClock()
        precondition(CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: host,
                                                    timebaseOut: &parent) == noErr)
        precondition(CMTimebaseCreateWithSourceTimebase(allocator: kCFAllocatorDefault, sourceTimebase: parent!,
                                                       timebaseOut: &child) == noErr)
        precondition(CMTimebaseSetTime(parent!, time: CMTime(seconds: 10, preferredTimescale: 48_000)) == noErr)
        precondition(CMTimebaseSetRate(parent!, rate: 0.75) == noErr)
        precondition(CMTimebaseSetTime(child!, time: CMTime(seconds: 23, preferredTimescale: 48_000)) == noErr)
        precondition(CMTimebaseSetRate(child!, rate: 1) == noErr)
        let first = CameraPlaybackClock.read(child!)!
        precondition(CMTimebaseGetRate(child!) == 1 && abs(first.rate - 0.75) < 0.000001,
                     "The recorder must include the parent timebase's playback rate")
        try await Task.sleep(nanoseconds: 30_000_000)
        let later = CameraPlaybackClock.read(child!)!
        precondition(later.host > first.host && later.position > first.position)
        precondition(abs((later.position - first.position) - (later.host - first.host) * 0.75) < 0.002)
        let beforePause = CMClockGetTime(host).seconds
        precondition(CMTimebaseSetRate(parent!, rate: 0) == noErr)
        let paused = CameraPlaybackClock.read(child!)!
        precondition(paused.rate == 0 && paused.changedAt >= beforePause - 0.001 && paused.changedAt <= paused.host)
        try await Task.sleep(nanoseconds: 30_000_000)
        let still = CameraPlaybackClock.read(child!)!
        precondition(abs(still.position - paused.position) < 0.000001 && still.host > paused.host)
        precondition(CMTimebaseSetTime(child!, time: CMTime(seconds: 5, preferredTimescale: 48_000)) == noErr)
        let seek = CameraPlaybackClock.read(child!)!
        precondition(abs(seek.position - 5) < 0.001 && seek.rate == 0)
        precondition(CMTimebaseSetRate(parent!, rate: 1.5) == noErr)
        let resumed = CameraPlaybackClock.read(child!)!
        precondition(abs(resumed.rate - 1.5) < 0.000001 && resumed.position.isFinite && resumed.position >= 5)
        precondition(resumed.changedAt >= seek.host - 0.001 && resumed.changedAt <= resumed.host)
        try await Task.sleep(nanoseconds: 30_000_000)
        let running = CameraPlaybackClock.read(child!)!
        precondition(abs((running.position - resumed.position) - (running.host - resumed.host) * 1.5) < 0.002)
        print("Native playback clock passed nested 0.75× rate, advancing source position, pause, seek and 1.5× resume.")
    }

    private static func timelineFailures() throws {
        let jitter = [CameraAudioSegment(hostStart: 0, hostEnd: 1), CameraAudioSegment(hostStart: 0.9995, hostEnd: 2)]
        let clipped = try CameraTimeline.clip(jitter, videoStart: 0, duration: 2)
        precondition(clipped.count == 2 && clipped[1].hostStart == 1)
        for bad in [
            [CameraAudioSegment(hostStart: 0, hostEnd: 1), CameraAudioSegment(hostStart: 0.8, hostEnd: 2)],
            [CameraAudioSegment(hostStart: 0, hostEnd: 1, sourceKey: "a", rate: 0)],
            [CameraAudioSegment(hostStart: .nan, hostEnd: 1)],
            [CameraAudioSegment(hostStart: 0, hostEnd: 1, sourceKey: "a", sourceStart: -1)],
        ] {
            do {
                _ = try CameraTimeline.clip(bad, videoStart: 0, duration: 2)
                preconditionFailure("Invalid source timing must be rejected")
            } catch is CameraExportError {}
        }
    }

    private static func tone(to url: URL, base: Double, step: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000)!
        buffer.frameLength = 480_000
        for frame in 0..<480_000 {
            let seconds = Double(frame) / 48_000
            let frequency = base + floor(seconds) * step
            let sample = Float(0.25 * sin(2 * .pi * frequency * seconds))
            buffer.floatChannelData![0][frame] = sample
            buffer.floatChannelData![1][frame] = sample
        }
        try file.write(from: buffer)
    }

    private static func video(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 80,
            AVVideoHeightKey: 48,
        ])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 80,
            kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<180 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error! }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var image: CVPixelBuffer?
            precondition(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &image) == kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(image!, [])
            let bytes = CVPixelBufferGetBaseAddress(image!)!
            memset(bytes, Int32(40 + frame % 180), CVPixelBufferGetDataSize(image!))
            CVPixelBufferUnlockBaseAddress(image!, [])
            precondition(adaptor.append(image!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 6, preferredTimescale: 30))
        await withCheckedContinuation { done in writer.finishWriting { done.resume() } }
        precondition(writer.status == .completed)
    }

    private static func decode(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        precondition(tracks.count == 1)
        let formats = try await tracks[0].load(.formatDescriptions)
        let format = CMAudioFormatDescriptionGetStreamBasicDescription(formats[0])!.pointee
        precondition(format.mSampleRate == 48_000 && format.mFormatID == kAudioFormatMPEG4AAC)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        precondition(reader.startReading())
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            let block = CMSampleBufferGetDataBuffer(sample)!
            var values = [Float](repeating: 0, count: count * 2)
            let status = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            precondition(status == noErr)
            let start = Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds * 48_000).rounded())
            if samples.count < start + count { samples += Array(repeating: 0, count: start + count - samples.count) }
            for index in 0..<count where start + index >= 0 { samples[start + index] = values[index * 2] }
        }
        precondition(reader.status == .completed)
        return samples
    }

    private static func rms(_ samples: [Float], at seconds: Double, frames count: Int = 4800) -> Double {
        let start = Int(seconds * 48_000)
        precondition(start >= 0 && start + count <= samples.count)
        let energy = samples[start..<(start + count)].reduce(0.0) { $0 + Double($1 * $1) }
        return sqrt(energy / Double(count))
    }

    private static func assertTone(_ samples: [Float], at seconds: Double, frequency: Double) throws {
        let start = Int(seconds * 48_000), count = 4800
        precondition(start + count < samples.count && rms(samples, at: seconds) > 0.04)
        var crossings = 0
        for index in (start + 1)..<(start + count) where samples[index - 1] <= 0 && samples[index] > 0 { crossings += 1 }
        let measured = Double(crossings) * 10
        precondition(abs(measured - frequency) <= 20, "Source offset or pitch mismatch, measured \(measured), expected \(frequency)")
    }
}
