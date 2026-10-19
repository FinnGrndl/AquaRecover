import FlutterMacOS
import Foundation

/// Flutter channel glue for macOS. Shares AquaMediaPipeline.swift with iOS so
/// video export uses AVFoundation + Core Image instead of an ffmpeg process,
/// which the App Sandbox cannot launch.
enum MacMediaProcessor {
  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let pipeline = AquaMediaPipeline()
    let activity = ProcessInfo.processInfo

    let videoChannel = FlutterMethodChannel(name: "aqua_recover/video", binaryMessenger: binaryMessenger)
    videoChannel.setMethodCallHandler { call, result in
      if call.method == "cancelRestoreVideo" {
        pipeline.cancelAllVideoExports()
        result(nil)
        return
      }
      guard call.method == "restoreVideo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "inputPath and outputPath are required", details: nil))
        return
      }
      // Keeps App Nap and idle sleep from throttling a long export.
      let token = activity.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled],
        reason: "AquaRecover video export"
      )
      let finish: (Any?) -> Void = { value in
        DispatchQueue.main.async {
          activity.endActivity(token)
          result(value)
        }
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try pipeline.restoreVideo(
            inputPath: inputPath,
            outputPath: outputPath,
            args: args,
            onExporterReady: { _ in }
          ) { exportResult in
            switch exportResult {
            case .success(let path):
              finish(path)
            case .failure(let error):
              finish(flutterError(error, code: "VIDEO_EXPORT_FAILED"))
            }
          }
        } catch {
          finish(flutterError(error, code: "VIDEO_EXPORT_FAILED"))
        }
      }
    }

    let imageChannel = FlutterMethodChannel(name: "aqua_recover/image", binaryMessenger: binaryMessenger)
    imageChannel.setMethodCallHandler { call, result in
      guard call.method == "restoreImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "inputPath and outputPath are required", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let restored = try pipeline.restoreImage(inputPath: inputPath, outputPath: outputPath, args: args)
          DispatchQueue.main.async { result(restored) }
        } catch {
          DispatchQueue.main.async { result(flutterError(error, code: "IMAGE_RESTORE_FAILED")) }
        }
      }
    }
  }

  private static func flutterError(_ error: Error, code: String) -> FlutterError {
    let resolvedCode = AquaMediaPipeline.isCancellation(error) ? "CANCELLED" : code
    return FlutterError(code: resolvedCode, message: error.localizedDescription, details: nil)
  }
}
