import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appearanceChannel: FlutterMethodChannel?
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
    let share = FlutterMethodChannel(name: "dev.hyperstream/share", binaryMessenger: registrar.messenger())
    share.setMethodCallHandler { call, result in
      guard call.method == "shareText", let text = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
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
      let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      presenter.present(controller, animated: true) { result(nil) }
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
