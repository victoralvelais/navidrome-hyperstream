import AVFoundation
import Foundation

/// Records the native player's transport clock. Flutter position updates are
/// deliberately excluded from export timing. Requests remain in memory only.
@MainActor
final class CameraPlayback {
    private struct Snapshot {
        let host: Double
        let source: String?
        let position: Double
        let rate: Double
        var preservesPitch: Bool = true
        var sourceEnd: Double? = nil
        var occurrence: ObjectIdentifier? = nil
        var changedAt: Double? = nil
    }
    private let provider: () -> AVQueuePlayer?
    private var player: AVQueuePlayer?
    private var observers: [NSKeyValueObservation] = []
    private var jumpObserver: NSObjectProtocol?
    private var timer: Timer?
    private var anchor: Snapshot?
    private var segments: [CameraAudioSegment] = []
    private var sourceKeys: [String: String] = [:]
    private var requests: [String: URLRequest] = [:]
    private var downloads: [String: Task<URL, Error>] = [:]
    private var directory: URL?
    private var recording = false
    private let unavailableSource = UUID().uuidString
    private let downloader: URLSession

    init(provider: @escaping () -> AVQueuePlayer?) {
        self.provider = provider
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        downloader = URLSession(configuration: config)
    }

    func begin(in directory: URL) {
        self.directory = directory
        recording = true
        bindPlayer()
        sample()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.bindPlayer()
                self?.sample()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        jumpObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemTimeJumped, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem, item === self.player?.currentItem else { return }
                self.sample(forceBoundary: true)
            }
        }
    }

    private func bindPlayer() {
        let current = provider()
        guard player !== current else { return }
        observers.removeAll()
        player = current
        guard let player else { return }
        let update: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.sample() }
        }
        observers = [
            player.observe(\.currentItem) { _, _ in update() },
            player.observe(\.rate) { _, _ in update() },
            player.observe(\.timeControlStatus) { _, _ in update() },
        ]
    }

    private func snapshot() -> Snapshot {
        let clock = CMClockGetHostTimeClock()
        let host = CMClockGetTime(clock).seconds
        guard let player, let item = player.currentItem, let timebase = item.timebase,
              let point = CameraPlaybackClock.read(timebase) else {
            return Snapshot(host: host, source: nil, position: 0, rate: 1)
        }
        guard player.timeControlStatus == .playing, point.rate >= 0.49, point.rate <= 2.01 else {
            return Snapshot(host: point.host, source: nil, position: 0, rate: 1,
                            occurrence: ObjectIdentifier(item), changedAt: point.changedAt)
        }
        let rate = min(2, max(0.5, point.rate))
        let preservesPitch = item.audioTimePitchAlgorithm != .varispeed
        // File, HTTP and authenticated proxy sources all retain the request
        // used by just_audio. The original player continues owning playback.
        let request = (item as? IndexedPlayerItem)?.hyperstreamSourceRequest
            ?? (item.asset as? AVURLAsset).map { URLRequest(url: $0.url) }
        guard let request, let url = request.url else {
            return Snapshot(host: point.host, source: unavailableSource, position: point.position, rate: rate,
                            preservesPitch: preservesPitch)
        }
        let identity = url.absoluteString
        let key = sourceKeys[identity] ?? UUID().uuidString
        sourceKeys[identity] = key
        requests[key] = request
        if downloads[key] == nil { downloads[key] = download(key: key, request: request) }
        let duration = item.duration.seconds
        return Snapshot(host: point.host, source: key, position: point.position, rate: rate,
                        preservesPitch: preservesPitch,
                        sourceEnd: duration.isFinite && duration > 0 ? duration : nil,
                        occurrence: ObjectIdentifier(item), changedAt: point.changedAt)
    }

    private func sample(forceBoundary: Bool = false) {
        guard recording else { return }
        var value = snapshot()
        guard let anchor else { self.anchor = value; return }
        if let change = value.changedAt, change >= anchor.host, change <= value.host,
           value.source != anchor.source || abs(value.rate - anchor.rate) > 0.0001 || forceBoundary {
            value = Snapshot(host: change, source: value.source,
                position: value.source == nil ? 0 : max(0, value.position - (value.host - change) * value.rate),
                rate: value.rate, preservesPitch: value.preservesPitch,
                sourceEnd: value.sourceEnd, occurrence: value.occurrence, changedAt: change)
        }
        if anchor.occurrence != nil, value.occurrence != nil, value.occurrence != anchor.occurrence,
           value.position < 0.25 * value.rate {
            // A queue-item notification may arrive just after audio starts.
            // Use its native clock to recover the start of that occurrence.
            let start = value.host - value.position / value.rate
            if start >= anchor.host {
                value = Snapshot(host: start, source: value.source, position: 0, rate: value.rate,
                                 preservesPitch: value.preservesPitch,
                                 sourceEnd: value.sourceEnd, occurrence: value.occurrence)
            }
        }
        let expected = anchor.position + (value.host - anchor.host) * anchor.rate
        let jumped = value.source != nil && abs(value.position - expected) > 0.06
        if forceBoundary || value.occurrence != anchor.occurrence || value.source != anchor.source || abs(value.rate - anchor.rate) > 0.0001 || value.preservesPitch != anchor.preservesPitch || jumped {
            append(until: value.host)
            self.anchor = value
        }
    }

    private func append(until host: Double) {
        guard let anchor, host > anchor.host else { return }
        let end = anchor.sourceEnd.map { min(host, max(anchor.host, anchor.host + ($0 - anchor.position) / anchor.rate)) } ?? host
        if end > anchor.host {
            segments.append(CameraAudioSegment(hostStart: anchor.host, hostEnd: end,
                sourceKey: anchor.source, sourceStart: anchor.position, rate: anchor.rate,
                preservesPitch: anchor.preservesPitch))
        }
        if host > end { segments.append(CameraAudioSegment(hostStart: end, hostEnd: host)) }
    }

    func finish() -> [CameraAudioSegment] {
        guard recording else { return segments }
        sample()
        append(until: CMClockGetTime(CMClockGetHostTimeClock()).seconds)
        recording = false
        timer?.invalidate()
        timer = nil
        observers.removeAll()
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        jumpObserver = nil
        player = nil
        return segments
    }

    func cancel() {
        _ = finish()
        for download in downloads.values { download.cancel() }
    }

    func sources(retry: Bool = false) async throws -> [String: URL] {
        var result: [String: URL] = [:]
        for key in Set(segments.compactMap(\.sourceKey)) {
            guard let request = requests[key] else {
                throw CameraFailure("The song's original audio is unavailable. Your camera video is kept for recovery.")
            }
            if retry, let task = downloads[key], case .failure = await task.result {
                downloads[key] = download(key: key, request: request)
            }
            guard let task = downloads[key] else { throw CameraFailure("The soundtrack is unavailable.") }
            do { result[key] = try await task.value }
            catch { throw CameraFailure("The soundtrack download could not finish. Check your connection and retry saving.") }
        }
        return result
    }

    private func download(key: String, request: URLRequest) -> Task<URL, Error> {
        let session = downloader
        let folder = directory!
        return Task {
            let target = folder.appendingPathComponent(key + ".audio")
            if FileManager.default.fileExists(atPath: target.path) { return target }
            try Task.checkCancellation()
            guard let url = request.url else { throw CameraFailure("The song source is unavailable.") }
            if url.isFileURL {
                let staging = folder.appendingPathComponent(UUID().uuidString + ".part")
                defer { try? FileManager.default.removeItem(at: staging) }
                try FileManager.default.copyItem(at: url, to: staging)
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: staging, to: target)
            } else {
                let (temporary, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw CameraFailure("The server could not provide the song.")
                }
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            return target
        }
    }
}
