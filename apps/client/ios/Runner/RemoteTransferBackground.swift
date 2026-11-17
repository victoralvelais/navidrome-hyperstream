import BackgroundTasks
import UIKit
import UserNotifications

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
    var notificationSent = false
    var notificationsAllowed = false

    init(token: String, reply: @escaping (String) -> Void) {
      self.token = token
      self.reply = reply
    }
  }

  var onExpired: ((String) -> Void)?
  private var session: Session?

  func begin(token: String, continued: Bool, reply: @escaping (String) -> Void) {
    guard session == nil, UIApplication.shared.applicationState == .active else {
      reply("foreground")
      return
    }
    let job = Session(token: token, reply: reply)
    session = job
    prepareNotifications(job)
    job.grace = UIApplication.shared.beginBackgroundTask(withName: "Send audio") { [weak self, weak job] in
      guard let self, let job, job.grace != .invalid else { return }
      self.expire(job)
    }
    // The initial transfer stays quiet. A foreground retry can explicitly opt
    // into iOS's visible continued-processing activity after an interruption.
    guard continued else {
      if #available(iOS 26.0, *), job.grace != .invalid {
        resolve(job, mode: "quiet")
      } else {
        resolve(job, mode: fallbackMode(job))
      }
      return
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

  private func prepareNotifications(_ job: Session) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      // Provisional permission delivers quietly to Notification Center and
      // respects an existing denial without opening a permission prompt.
      if settings.authorizationStatus == .notDetermined {
        center.requestAuthorization(options: [.alert, .provisional]) { granted, _ in
          DispatchQueue.main.async { job.notificationsAllowed = granted }
        }
      } else {
        DispatchQueue.main.async {
          job.notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
      }
    }
  }

  func notifyResult(token: String, success: Bool, reply: @escaping (Bool) -> Void) {
    guard let job = session, job.token == token,
          UIApplication.shared.applicationState != .active else {
      reply(false)
      return
    }
    if job.notificationSent && !success {
      reply(true)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        guard UIApplication.shared.applicationState != .active,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
          reply(false)
          return
        }
        Self.postNotification(job, success: success, reply: reply)
      }
    }
  }

  private static func postNotification(_ job: Session, success: Bool, reply: @escaping (Bool) -> Void) {
    let content = UNMutableNotificationContent()
    content.title = success ? "Song sent" : "Transfer interrupted"
    content.body = success
      ? "Your song was sent to the remote folder."
      : "Open Hyperstream to review the issue and retry."
    content.threadIdentifier = "hyperstream.remote-transfer"
    content.interruptionLevel = success ? .passive : .active
    let request = UNNotificationRequest(
      identifier: "hyperstream.remote-transfer." + job.token, content: content, trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        job.notificationSent = error == nil
        reply(error == nil)
      }
    }
  }

  /// Private transfer and extension storage remains encrypted and readable after lock.
  /// Files created inside it inherit the protection class.
  static func prepareDirectory(path: String) throws {
    let manager = FileManager.default
    guard let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
          let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw CocoaError(.fileNoSuchFile)
    }
    let transferRoot = cache.appendingPathComponent("hyperstream-share", isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    let extensionRoot = support.appendingPathComponent("music-extensions", isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    let directory = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
    let isTransferDirectory = directory.path.hasPrefix(transferRoot.path + "/")
    let isExtensionDirectory = directory.path == extensionRoot.path
      || directory.path.hasPrefix(extensionRoot.path + "/")
    guard (isTransferDirectory || isExtensionDirectory), values.isDirectory == true else {
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
    // Enqueue before ending the grant, without waiting for an asynchronous
    // settings query. The system still enforces current notification permissions.
    if job.notificationsAllowed && UIApplication.shared.applicationState != .active {
      Self.postNotification(job, success: false) { _ in }
    }
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
