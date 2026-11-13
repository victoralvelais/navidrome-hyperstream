import Flutter
import UIKit
import AVKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appearanceChannel: FlutterMethodChannel?
  private var artworkChannel: FlutterMethodChannel?
  private var shareChannel: FlutterMethodChannel?
  private var sharing = false
  private var transparencyObserver: NSObjectProtocol?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HyperstreamAppearance") else { return }
    registrar.register(HyperstreamRouteFactory(), withId: "dev.hyperstream/audio_route_picker")
    let artwork = FlutterMethodChannel(name: "dev.hyperstream/system_artwork", binaryMessenger: registrar.messenger())
    artworkChannel = artwork
    artwork.setMethodCallHandler { call, result in
      guard call.method == "decodePNG" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let bytes = call.arguments as? FlutterStandardTypedData else {
        result(nil)
        return
      }
      let input = bytes.data
      DispatchQueue.global(qos: .utility).async {
        let png = autoreleasepool { SystemArtwork.pngData(input) }
        DispatchQueue.main.async {
          result(png.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    }
    let share = FlutterMethodChannel(name: "dev.hyperstream/share", binaryMessenger: registrar.messenger())
    shareChannel = share
    share.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self, !self.sharing else {
        result(FlutterError(code: "busy", message: "Sharing is already open.", details: nil))
        return
      }
      guard let path = call.arguments as? String,
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        result(FlutterError(code: "invalid_file", message: "The audio file is unavailable.", details: nil))
        return
      }
      let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      let root = cache.appendingPathComponent("hyperstream-share", isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath()
      let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard file.path.hasPrefix(root.path + "/"),
            values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 else {
        result(FlutterError(code: "invalid_file", message: "The audio file is unavailable.", details: nil))
        return
      }
      guard var presenter = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .filter({ $0.activationState == .foregroundActive })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "unavailable", message: "Share is unavailable.", details: nil))
        return
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      guard !(presenter is UIActivityViewController), !presenter.isBeingDismissed else {
        result(FlutterError(code: "busy", message: "Another sheet is closing. Try again.", details: nil))
        return
      }
      // A typed local file is the sole item. Discord receives an attachment,
      // never an authenticated Navidrome URL or a text-only song description.
      let controller = UIActivityViewController(activityItems: [HyperstreamAudioItem(file: file)], applicationActivities: nil)
      self.sharing = true
      controller.completionWithItemsHandler = { [weak self] _, completed, _, error in
        self?.sharing = false
        if error != nil {
          result(FlutterError(code: "share_failed", message: "Audio sharing could not finish.", details: nil))
        } else {
          result(completed)
        }
      }
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      presenter.present(controller, animated: true)
    }
    let channel = FlutterMethodChannel(name: "dev.hyperstream/appearance", binaryMessenger: registrar.messenger())
    appearanceChannel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "reduceTransparency" {
        result(UIAccessibility.isReduceTransparencyEnabled)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    if let observer = transparencyObserver { NotificationCenter.default.removeObserver(observer) }
    transparencyObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      self?.appearanceChannel?.invokeMethod("reduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled)
    }
  }

  deinit {
    if let observer = transparencyObserver { NotificationCenter.default.removeObserver(observer) }
  }
}

private class HyperstreamAudioItem: NSObject, UIActivityItemSource {
  let file: URL
  init(file: URL) {
    self.file = file
    super.init()
  }
  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { file }
  func activityViewController(_ activityViewController: UIActivityViewController,
                              itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { file }
  func activityViewController(_ activityViewController: UIActivityViewController,
                              dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
    (UTType(filenameExtension: file.pathExtension) ?? .data).identifier
  }
  func activityViewController(_ activityViewController: UIActivityViewController,
                              subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
    file.deletingPathExtension().lastPathComponent
  }
}

private class HyperstreamRouteFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    HyperstreamRouteView(frame: frame, arguments: args)
  }
}

private class HyperstreamRouteView: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView
  init(frame: CGRect, arguments: Any?) {
    picker = AVRoutePickerView(frame: frame)
    super.init()
    let params = arguments as? [String: Any]
    let dark = params?["dark"] as? Bool ?? false
    func color(_ key: String, fallback: UIColor) -> UIColor {
      guard let value = params?[key] as? NSNumber else { return fallback }
      let argb = value.uint32Value
      return UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                     green: CGFloat((argb >> 8) & 255) / 255,
                     blue: CGFloat(argb & 255) / 255,
                     alpha: CGFloat((argb >> 24) & 255) / 255)
    }
    picker.backgroundColor = .clear
    picker.isOpaque = false
    picker.overrideUserInterfaceStyle = dark ? .dark : .light
    picker.tintColor = color("tint", fallback: dark ? .white : .black)
    picker.activeTintColor = color("activeTint", fallback: .systemPurple)
    picker.prioritizesVideoDevices = false
    picker.accessibilityLabel = "Choose audio output"
  }
  func view() -> UIView { picker }
}
