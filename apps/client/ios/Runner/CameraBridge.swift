import AVFoundation
import Flutter
import ReplayKit
import UIKit

@MainActor
final class CameraBridge {
    private let channel: FlutterMethodChannel
    private let capture: CameraCapture
    private let player: () -> AVQueuePlayer?
    private let takes = CameraTakes()
    private var playback: CameraPlayback?
    private var pendingPlayback: [String: CameraPlayback] = [:]
    private var folder: URL?
    private var phase = "idle"
    private var active = false
    private var ready = false
    private var front = false
    private var aspect = 9.0 / 16.0
    private var originalTempo = false
    private var message = ""
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var wasIdleTimerDisabled = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry, player: @escaping () -> AVQueuePlayer?) {
        self.player = player
        channel = FlutterMethodChannel(name: "dev.hyperstream/camera", binaryMessenger: messenger)
        capture = CameraCapture(textures: textures)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            self.handle(call, result: result)
        }
        capture.onFrame = { [weak self] ratio, front in
            guard let self, self.active else { return }
            if !self.ready || self.aspect != ratio || self.front != front {
                self.ready = true
                self.aspect = ratio
                self.front = front
                self.publish()
            }
        }
        capture.onFailure = { [weak self] message in
            guard let self, self.phase == "recording" || self.phase == "starting" else { return }
            self.playback?.cancel()
            self.playback = nil
            self.phase = "idle"
            self.message = message
            self.publish()
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stop()
                self.capture.close()
                self.ready = false
                self.publish()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active, !self.ready else { return }
                self.configure()
            }
        })
        observers.append(center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        })
    }

    private var state: [String: Any] {
        ["texture": capture.textureID, "ready": ready, "front": front,
         "aspect": aspect, "phase": phase, "message": message,
         "pending": takes.pendingCount, "report": takes.report,
         "captured": UIScreen.main.isCaptured]
    }

    private func publish() { channel.invokeMethod("state", arguments: state) }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "open":
            if !active { wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled }
            active = true
            UIApplication.shared.isIdleTimerDisabled = true
            result(state)
            configure()
        case "close":
            active = false
            generation += 1
            stop()
            capture.close()
            ready = false
            UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
            result(nil)
        case "switchCamera":
            guard phase == "idle", active else { result(nil); return }
            ready = false
            configure(front: !front)
            result(nil)
        case "start":
            start(originalTempo: (call.arguments as? [String: Any])?["originalTempo"] as? Bool ?? false)
            result(nil)
        case "stop":
            stop()
            result(nil)
        case "retry":
            retry()
            result(nil)
        case "recoverVideo":
            guard let url = takes.rawRecovery() else { result(nil); return }
            share(url)
            result(nil)
        case "dismissMessage":
            message = ""
            publish()
            result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func configure(front requested: Bool? = nil) {
        guard active else { return }
        generation += 1
        let request = generation
        let position = requested ?? front
        Task {
            let authorized = await AVCaptureDevice.requestAccess(for: .video)
            guard active, generation == request else { return }
            guard authorized else {
                message = "Allow camera access in iPhone Settings to open the preview."
                publish()
                return
            }
            capture.configure(front: position) { [weak self] error in
                guard let self, self.active, self.generation == request else { return }
                if let error { self.message = error.localizedDescription }
                self.publish()
            }
        }
    }

    private func start(originalTempo: Bool) {
        guard active, ready, phase == "idle" else { return }
        self.originalTempo = originalTempo
        do {
            let directory = try takes.create()
            let playback = CameraPlayback(provider: player)
            self.playback = playback
            folder = directory
            playback.begin(in: directory)
            phase = "starting"
            message = ""
            publish()
            capture.begin(to: directory.appendingPathComponent("raw.mov")) { [weak self] error in
                guard let self, self.folder == directory, self.phase == "starting" else { return }
                if let error {
                    self.playback?.cancel()
                    self.playback = nil
                    self.phase = "idle"
                    self.message = error.localizedDescription
                } else if self.phase == "starting" { self.phase = "recording" }
                self.publish()
            }
        } catch { message = error.localizedDescription; publish() }
    }

    private func stop() {
        guard phase == "recording" || phase == "starting",
              let folder, let playback else { return }
        phase = "saving"
        let restore = originalTempo
        let segments = playback.finish()
        self.playback = nil
        pendingPlayback[folder.lastPathComponent] = playback
        beginBackgroundSave()
        publish()
        capture.finish { [weak self] result in
            guard let self, self.folder == folder else { return }
            Task {
                do {
                    let movie = try result.get()
                    try self.takes.prepare(folder, movie: movie, segments: segments, restoreTempo: restore)
                    let sources = try await playback.sources()
                    try await self.takes.save(folder, sources: sources)
                    self.pendingPlayback.removeValue(forKey: folder.lastPathComponent)
                    self.message = "Saved to Photos."
                } catch { self.message = error.localizedDescription }
                self.phase = "idle"
                self.endBackgroundSave()
                self.publish()
            }
        }
    }

    private func retry() {
        guard phase == "idle" else { return }
        phase = "saving"
        message = ""
        beginBackgroundSave()
        publish()
        Task {
            var saved = 0
            var problems: [String] = []
            for folder in takes.pendingFolders() {
                do {
                    let sources = try await pendingPlayback[folder.lastPathComponent]?.sources(retry: true)
                    try await takes.save(folder, sources: sources)
                    pendingPlayback.removeValue(forKey: folder.lastPathComponent)
                    saved += 1
                } catch { problems.append(error.localizedDescription) }
            }
            message = problems.first.map { "\(saved) saved. \(problems.count) pending. \($0)" } ?? "Saved to Photos."
            phase = "idle"
            endBackgroundSave()
            publish()
        }
    }

    private func beginBackgroundSave() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish camera take") { [weak self] in
            // The manifest and raw video allow foreground retry after suspension.
            self?.endBackgroundSave()
        }
    }

    private func endBackgroundSave() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func share(_ url: URL) {
        guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }
}

final class HyperstreamBroadcastFactory: NSObject, FlutterPlatformViewFactory {
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        HyperstreamBroadcastView(frame: frame)
    }
}

final class HyperstreamBroadcastView: NSObject, FlutterPlatformView {
    private let picker: RPSystemBroadcastPickerView
    init(frame: CGRect) {
        picker = RPSystemBroadcastPickerView(frame: frame)
        picker.showsMicrophoneButton = true
        picker.tintColor = .white
        super.init()
    }
    func view() -> UIView { picker }
}
