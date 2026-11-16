import Foundation
import Photos

/// Keeps the original movie and authenticated-download results inside a private
/// take directory until Photos confirms delivery. The manifest contains no URLs.
@MainActor
final class CameraTakes {
    private struct Manifest: Codable {
        var version = 1
        let videoStart: Double
        let segments: [CameraAudioSegment]
        let restoreTempo: Bool
        var photosAttempted = false
        var delivered = false
    }

    private let root: URL
    private var saving = Set<URL>()
    private(set) var report: String

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CameraTakes", isDirectory: true)
        report = (try? String(contentsOf: root.appendingPathComponent("latest-report.txt"), encoding: .utf8)) ?? ""
    }

    var pendingCount: Int { pendingFolders().count }

    func create() throws -> URL {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            return folder
        } catch { throw CameraFailure("There is not enough available storage to start a take.") }
    }

    func prepare(_ folder: URL, movie: CameraMovie, segments: [CameraAudioSegment], restoreTempo: Bool) throws {
        let folder = try checkedFolder(folder)
        let raw = folder.appendingPathComponent("raw.mov")
        guard movie.url.standardizedFileURL.resolvingSymlinksInPath() == raw,
              FileManager.default.fileExists(atPath: raw.path) else {
            throw CameraFailure("The original camera file is unavailable.")
        }
        let manifest = Manifest(videoStart: movie.hostStart, segments: segments, restoreTempo: restoreTempo)
        try validate(manifest)
        try write(manifest, in: folder)
    }

    func pendingFolders() -> [URL] {
        folders().filter { folder in
            if let manifest = try? read(in: folder), manifest.delivered { return false }
            return FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) ||
                FileManager.default.fileExists(atPath: folder.appendingPathComponent("raw.mov").path)
        }
    }

    func rawRecovery() -> [URL] {
        pendingFolders().reversed().map { $0.appendingPathComponent("raw.mov") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func save(_ folder: URL, sources: [String: URL]? = nil) async throws {
        let folder = try checkedFolder(folder)
        guard !saving.contains(folder) else { throw CameraFailure("This take is already being saved.") }
        saving.insert(folder)
        defer { saving.remove(folder) }
        var manifest = try read(in: folder)
        let exported = folder.appendingPathComponent("exported.mp4")
        if manifest.delivered {
            try? FileManager.default.removeItem(at: folder)
            return
        }
        // Photos moves the export only on successful delivery. This also recovers
        // an app termination between that move and writing our local receipt.
        if manifest.photosAttempted && !FileManager.default.fileExists(atPath: exported.path) {
            complete(&manifest, in: folder)
            return
        }
        if !FileManager.default.fileExists(atPath: exported.path) {
            let cached = try cacheSources(sources ?? [:], for: manifest, in: folder)
            let result = try await CameraExport.save(video: folder.appendingPathComponent("raw.mov"),
                                                     segments: manifest.segments, sources: cached,
                                                     videoStart: manifest.videoStart, restoreTempo: manifest.restoreTempo,
                                                     to: exported)
            writeReport(manifest, result: result)
        }
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            throw CameraFailure("Allow Photos additions in Settings, then retry. Your take is kept on this device.")
        }
        manifest.photosAttempted = true
        try write(manifest, in: folder)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: exported, options: options)
            }
        } catch {
            throw CameraFailure("Photos could not finish saving. Your take is kept on this device for retry.")
        }
        complete(&manifest, in: folder)
    }

    private func complete(_ manifest: inout Manifest, in folder: URL) {
        manifest.delivered = true
        // Persist the receipt before cleanup. A cleanup failure leaves a delivered
        // take excluded from automatic retries and prevents duplicate Photos items.
        try? write(manifest, in: folder)
        try? FileManager.default.removeItem(at: folder)
    }

    private func cacheSources(_ sources: [String: URL], for manifest: Manifest, in folder: URL) throws -> [String: URL] {
        var cached: [String: URL] = [:]
        for key in Set(manifest.segments.compactMap(\.sourceKey)) {
            // validate() has already restricted this filename to a UUID.
            let destination = folder.appendingPathComponent(key + ".audio")
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let source = sources[key], source.isFileURL,
                      FileManager.default.fileExists(atPath: source.path) else {
                    throw CameraFailure("A song needed for this take was not saved before the app closed. Use Recover original camera video to keep the footage.")
                }
                let staging = folder.appendingPathComponent(UUID().uuidString + ".part")
                defer { try? FileManager.default.removeItem(at: staging) }
                do {
                    try FileManager.default.copyItem(at: source, to: staging)
                    try FileManager.default.moveItem(at: staging, to: destination)
                } catch { throw CameraFailure("The music could not be stored for this take. Free some storage and retry.") }
            }
            cached[key] = destination
        }
        return cached
    }

    private func read(in folder: URL) throws -> Manifest {
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            try validate(manifest)
            return manifest
        } catch {
            throw CameraFailure("The take's music timing is unavailable. You can still share the original camera video.")
        }
    }

    private func write(_ manifest: Manifest, in folder: URL) throws {
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        } catch { throw CameraFailure("The take's recovery information could not be saved. Free some storage and retry.") }
    }

    private func validate(_ manifest: Manifest) throws {
        guard manifest.version == 1, manifest.videoStart.isFinite else {
            throw CameraFailure("The take's music timing is unavailable.")
        }
        for segment in manifest.segments {
            guard segment.hostStart.isFinite, segment.hostEnd.isFinite,
                  segment.hostEnd >= segment.hostStart, segment.sourceStart.isFinite, segment.sourceStart >= 0,
                  segment.rate.isFinite,
                  segment.sourceKey == nil || ((0.5...2).contains(segment.rate) &&
                      segment.sourceKey!.count == 36 && UUID(uuidString: segment.sourceKey!) != nil) else {
                throw CameraFailure("The take's music timing could not be verified.")
            }
        }
    }

    private func checkedFolder(_ folder: URL) throws -> URL {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent() == resolvedRoot,
              UUID(uuidString: resolved.lastPathComponent) != nil else {
            throw CameraFailure("The take's private storage is unavailable.")
        }
        return resolved
    }

    private func folders() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root,
                       includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
        return entries.compactMap { entry in
            guard let folder = try? checkedFolder(entry),
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return folder
        }.sorted {
            let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return first < second
        }
    }

    private func writeReport(_ manifest: Manifest, result: CameraExport.Result) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let rates = Set(manifest.segments.filter { $0.sourceKey != nil }.map(\.rate)).sorted()
            .map { String(format: "%.2f×", $0) }.joined(separator: ", ")
        report = [
            "Hyperstream \(version)",
            "Source soundtrack reconstructed from native playback timing.",
            "Finish at original song tempo  " + (manifest.restoreTempo ? "On" : "Off"),
            "Playback rates  " + (rates.isEmpty ? "Paused" : rates),
            "Music intervals  \(result.audioSegments)",
            String(format: "Export duration  %.3f seconds", result.duration),
            "Audio  48 kHz stereo AAC",
        ].joined(separator: "\n")
        try? report.write(to: root.appendingPathComponent("latest-report.txt"), atomically: true, encoding: .utf8)
    }
}
