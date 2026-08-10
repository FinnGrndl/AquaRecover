import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "AquaRecoverRawBridge") {
      RawBridge.register(binaryMessenger: registrar.messenger())
    }
    if let registrar = registrar(forPlugin: "AquaRecoverVideoProcessor") {
      IosVideoProcessor.register(binaryMessenger: registrar.messenger())
    }
    if let registrar = registrar(forPlugin: "AquaRecoverDeviceInfo") {
      let deviceChannel = FlutterMethodChannel(
        name: "aqua_recover/device",
        binaryMessenger: registrar.messenger()
      )
      deviceChannel.setMethodCallHandler { call, result in
        guard call.method == "isPad" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(UIDevice.current.userInterfaceIdiom == .pad)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
