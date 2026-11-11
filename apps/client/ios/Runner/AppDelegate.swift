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
    let dark = (arguments as? [String: Any])?["dark"] as? Bool ?? false
    picker.overrideUserInterfaceStyle = dark ? .dark : .light
    picker.tintColor = dark ? .white : .black
    picker.activeTintColor = .systemPink
    picker.prioritizesVideoDevices = false
    picker.accessibilityLabel = "Choose audio output"
  }
  func view() -> UIView { picker }
}
