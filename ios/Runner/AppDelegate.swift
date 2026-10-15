import Flutter
import UIKit
import AuthenticationServices

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeAppleSignInButton") {
      registrar.register(
        AppleSignInButtonFactory(messenger: registrar.messenger()),
        withId: "cd.dame/apple-sign-in-button"
      )
    }
  }
}

final class AppleSignInButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    AppleSignInButtonView(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
  }
}

final class AppleSignInButtonView: NSObject, FlutterPlatformView {
  private let button = ASAuthorizationAppleIDButton(type: .continue, style: .white)
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "cd.dame/apple-sign-in-button/\(viewId)", binaryMessenger: messenger)
    super.init()
    button.frame = frame
    button.cornerRadius = 8
    button.isEnabled = (arguments as? [String: Any])?["enabled"] as? Bool ?? true
    button.addTarget(self, action: #selector(onPressed), for: .touchUpInside)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setEnabled", let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.button.isEnabled = enabled
      result(nil)
    }
  }

  func view() -> UIView { button }

  @objc private func onPressed() {
    channel.invokeMethod("onPressed", arguments: nil)
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}
