import BackgroundTasks
import UIKit

/// Keeps a user-started SMB export running while Flutter's window is backgrounded.
/// All state is owned by the main queue. The transfer itself stays in Dart/SMB workers.
final class RemoteTransferBackground {
  private final class Session {
    let token: String
    var reply: ((String) -> Void)?
    var grace = UIBackgroundTaskIdentifier.invalid
    var task: BGTask?
    var requestIdentifier: String?
    var timeout: DispatchWorkItem?
    var expired = false

    init(token: String, reply: @escaping (String) -> Void) {
      self.token = token
      self.reply = reply
    }
  }

  var onExpired: ((String) -> Void)?
  private var session: Session?

  func begin(token: String, reply: @escaping (String) -> Void) {
    guard session == nil, UIApplication.shared.applicationState == .active else {
      reply("foreground")
      return
    }
    let job = Session(token: token, reply: reply)
    session = job
    job.grace = UIApplication.shared.beginBackgroundTask(withName: "Send audio") { [weak self, weak job] in
      guard let self, let job, job.grace != .invalid else { return }
      self.expire(job)
    }
    guard #available(iOS 26.0, *), let bundle = Bundle.main.bundleIdentifier else {
      resolve(job, mode: fallbackMode(job))
      return
    }

    // A distinct identifier prevents a delayed launch from attaching to a later
    // transfer. Only weak references remain in the scheduler's launch handler.
    let identifier = bundle + ".remoteTransfer." + UUID().uuidString
    let scheduler = BGTaskScheduler.shared
    let registered = scheduler.register(forTaskWithIdentifier: identifier, using: .main) { [weak self, weak job] task in
      guard let self, let job, self.session === job, job.reply != nil,
            !job.expired, let continued = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      job.task = continued
      continued.progress.totalUnitCount = -1
      continued.expirationHandler = { [weak self, weak job] in
        DispatchQueue.main.async {
          guard let self, let job else { return }
          self.expire(job)
        }
      }
      self.endGrace(job)
      self.resolve(job, mode: "continued")
    }
    guard registered else {
      resolve(job, mode: fallbackMode(job))
      return
    }
    job.requestIdentifier = identifier
    let request = BGContinuedProcessingTaskRequest(
      identifier: identifier, title: "Sending audio", subtitle: "Connecting"
    )
    request.strategy = .fail
    do {
      try scheduler.submit(request)
      // A successful submission is not an execution grant. Bound the wait if
      // the system never delivers its launch callback, then use the short grant.
      if job.reply != nil {
        let timeout = DispatchWorkItem { [weak self, weak job] in
          guard let self, let job, self.session === job, job.reply != nil else { return }
          scheduler.cancel(taskRequestWithIdentifier: identifier)
          self.resolve(job, mode: self.fallbackMode(job))
        }
        job.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
      }
    } catch {
      resolve(job, mode: fallbackMode(job))
    }
  }

  func update(token: String, completed: Int64, total: Int64, stage: String) {
    guard let job = session, job.token == token, !job.expired,
          #available(iOS 26.0, *), let task = job.task as? BGContinuedProcessingTask else { return }
    task.progress.totalUnitCount = total > 0 ? total : -1
    task.progress.completedUnitCount = max(0, completed)
    task.updateTitle("Sending audio", subtitle: stage)
  }

  func finish(token: String, success: Bool) {
    guard let job = session, job.token == token else { return }
    resolve(job, mode: "foreground")
    stop(job, success: success && !job.expired)
    session = nil
  }

  /// This private staging directory remains encrypted and readable after lock.
  /// Files created inside it inherit the protection class.
  static func prepareDirectory(path: String) throws {
    let manager = FileManager.default
    guard let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      throw CocoaError(.fileNoSuchFile)
    }
    let root = cache.appendingPathComponent("hyperstream-share", isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    let directory = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
    guard directory.path.hasPrefix(root.path + "/"), values.isDirectory == true else {
      throw CocoaError(.fileWriteNoPermission)
    }
    try manager.setAttributes([
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
    ], ofItemAtPath: directory.path)
  }

  private func fallbackMode(_ job: Session) -> String {
    job.grace == .invalid ? "foreground" : "limited"
  }

  private func resolve(_ job: Session, mode: String) {
    job.timeout?.cancel()
    job.timeout = nil
    let reply = job.reply
    job.reply = nil
    reply?(mode)
  }

  private func expire(_ job: Session) {
    guard session === job, !job.expired else { return }
    job.expired = true
    onExpired?(job.token)
    resolve(job, mode: "foreground")
    stop(job, success: false)
  }

  private func stop(_ job: Session, success: Bool) {
    if #available(iOS 26.0, *), let task = job.task as? BGContinuedProcessingTask, success {
      task.progress.completedUnitCount = task.progress.totalUnitCount
    }
    job.task?.setTaskCompleted(success: success)
    job.task = nil
    if let identifier = job.requestIdentifier {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
      job.requestIdentifier = nil
    }
    endGrace(job)
  }

  private func endGrace(_ job: Session) {
    guard job.grace != .invalid else { return }
    UIApplication.shared.endBackgroundTask(job.grace)
    job.grace = .invalid
  }
}
