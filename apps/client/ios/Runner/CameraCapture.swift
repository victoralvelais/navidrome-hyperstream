import AVFoundation
import Flutter

struct CameraMovie {
    let url: URL
    let hostStart: Double
}

struct CameraFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// The same pixel-buffer output feeds the Flutter compositor and the movie.
/// Its capture/session state is confined to queue. The texture buffer has a
/// separate short lock because Flutter reads it on its raster thread.
final class CameraCapture: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "hyperstream.camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let textures: FlutterTextureRegistry
    private let bufferLock = NSLock()
    private var latest: CVPixelBuffer?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var destination: URL?
    private var firstHost: Double?
    private var wantsFrames = false
    private var front = false
    private var start: ((Error?) -> Void)?
    private var notifications: [NSObjectProtocol] = []
    private(set) var textureID: Int64 = -1
    var onFrame: ((Double, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onInterruption: (() -> Void)?
    var onResumed: (() -> Void)?

    init(textures: FlutterTextureRegistry) {
        self.textures = textures
        super.init()
        textureID = textures.register(self)
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                self?.onInterruption?()
            })
        }
        notifications.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
            object: session, queue: .main) { [weak self] _ in self?.onResumed?() })
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return latest.map { Unmanaged.passRetained($0) }
    }

    func configure(front: Bool, completion: @escaping (Error?) -> Void) {
        queue.async {
            guard self.destination == nil else {
                DispatchQueue.main.async { completion(CameraFailure("Finish the take before switching cameras.")) }
                return
            }
            do {
                let position: AVCaptureDevice.Position = front ? .front : .back
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                    throw CameraFailure("This camera is unavailable.")
                }
                let replacement = try AVCaptureDeviceInput(device: camera)
                let previous = self.session.inputs
                self.session.beginConfiguration()
                self.session.automaticallyConfiguresApplicationAudioSession = false
                for old in previous { self.session.removeInput(old) }
                guard self.session.canAddInput(replacement) else {
                    for old in previous where self.session.canAddInput(old) { self.session.addInput(old) }
                    self.session.commitConfiguration()
                    throw CameraFailure("The camera could not switch. Try again.")
                }
                self.session.addInput(replacement)
                if !self.session.outputs.contains(self.output) {
                    guard self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration()
                        throw CameraFailure("Camera frames are unavailable.")
                    }
                    self.session.addOutput(self.output)
                }
                if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
                self.output.alwaysDiscardsLateVideoFrames = true
                self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                self.output.setSampleBufferDelegate(self, queue: self.queue)
                if let connection = self.output.connection(with: .video) {
                    if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }
                self.session.commitConfiguration()
                self.front = front
                self.wantsFrames = true
                if !self.session.isRunning { self.session.startRunning() }
                guard self.session.isRunning else { throw CameraFailure("The camera is unavailable. Reopen Camera to try again.") }
                DispatchQueue.main.async { completion(nil) }
            } catch { DispatchQueue.main.async { completion(error) } }
        }
    }

    func begin(to url: URL, completion: @escaping (Error?) -> Void) {
        queue.async {
            guard self.session.isRunning, self.destination == nil else {
                DispatchQueue.main.async { completion(CameraFailure("Wait for the camera preview, then try again.")) }
                return
            }
            self.destination = url
            self.firstHost = nil
            self.start = completion
            self.queue.asyncAfter(deadline: .now() + 4) {
                guard self.destination == url, self.start != nil else { return }
                self.fail(CameraFailure("The camera stopped delivering frames. Try again."))
            }
        }
    }

    func finish(completion: @escaping (Result<CameraMovie, Error>) -> Void) {
        queue.async {
            guard let writer = self.writer, let input = self.input,
                  let url = self.destination, let host = self.firstHost else {
                self.fail(CameraFailure("The camera did not record a frame."))
                DispatchQueue.main.async { completion(.failure(CameraFailure("The take was too short. Try again."))) }
                return
            }
            self.writer = nil
            self.input = nil
            self.destination = nil
            self.firstHost = nil
            input.markAsFinished()
            writer.finishWriting {
                let result: Result<CameraMovie, Error> = writer.status == .completed
                    ? .success(CameraMovie(url: url, hostStart: host))
                    : .failure(CameraFailure("The video could not finish writing. Check available storage."))
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    func close() {
        queue.async {
            self.wantsFrames = false
            if self.session.isRunning { self.session.stopRunning() }
            self.bufferLock.lock()
            self.latest = nil
            self.bufferLock.unlock()
        }
    }

    private func fail(_ error: Error) {
        writer?.cancelWriting()
        writer = nil
        input = nil
        destination = nil
        firstHost = nil
        let pending = start
        start = nil
        DispatchQueue.main.async {
            if let pending { pending(error) }
            else { self.onFailure?(error.localizedDescription) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard wantsFrames, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        bufferLock.lock()
        latest = buffer
        bufferLock.unlock()
        let ratio = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
        let front = self.front
        DispatchQueue.main.async {
            self.textures.textureFrameAvailable(self.textureID)
            self.onFrame?(ratio, front)
        }
        guard let url = destination else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        do {
            if writer == nil {
                let sessionClock: CMClock?
                if #available(iOS 15.4, *) { sessionClock = session.synchronizationClock }
                else { sessionClock = session.masterClock }
                guard let clock = sessionClock else { throw CameraFailure("Camera timing is unavailable.") }
                let host = CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock()).seconds
                guard host.isFinite else { throw CameraFailure("Camera timing is invalid.") }
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: CVPixelBufferGetWidth(buffer),
                    AVVideoHeightKey: CVPixelBufferGetHeight(buffer),
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
                ])
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw CameraFailure("Video encoding is unavailable.") }
                writer.add(input)
                guard writer.startWriting() else { throw CameraFailure("Could not create the video. Check available storage.") }
                writer.startSession(atSourceTime: pts)
                self.writer = writer
                self.input = input
                firstHost = host
            }
            guard let writer, let input else { return }
            if writer.status == .failed { throw CameraFailure("Video recording stopped. Check available storage.") }
            if input.isReadyForMoreMediaData {
                guard input.append(sample) else { throw CameraFailure("The camera could not write the video frame.") }
                if let start {
                    self.start = nil
                    DispatchQueue.main.async { start(nil) }
                }
            }
        } catch { fail(error) }
    }
}
