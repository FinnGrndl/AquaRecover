import AVFoundation
import BackgroundTasks
import Flutter
import Foundation
import UIKit

private protocol VideoExportActivity: AnyObject {
  func attach(exporter: AVAssetExportSession)
  func finish(success: Bool)
}

private final class BackgroundTaskLease: VideoExportActivity {
  private var identifier: UIBackgroundTaskIdentifier = .invalid

  init(name: String) {
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.end()
    }
  }

  func attach(exporter: AVAssetExportSession) {}

  func finish(success: Bool) {
    end()
  }

  private func end() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.end() }
      return
    }
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
  }
}

@available(iOS 26.0, *)
private final class ContinuedVideoExportActivity: VideoExportActivity {
  private let task: BGContinuedProcessingTask
  private var exporter: AVAssetExportSession?
  private var progressTimer: Timer?
  private var expired = false

  init(task: BGContinuedProcessingTask) {
    self.task = task
    task.progress.totalUnitCount = 100
    task.progress.completedUnitCount = 0
    task.expirationHandler = { [weak self] in
      self?.expire()
    }
  }

  func attach(exporter: AVAssetExportSession) {
    runOnMain { [weak self] in
      guard let self else { return }
      self.exporter = exporter
      if self.expired {
        exporter.cancelExport()
        return
      }
      self.progressTimer?.invalidate()
      self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
        [weak self, weak exporter] _ in
        guard let self, let exporter else { return }
        let completed = Int64((Double(exporter.progress) * 100).rounded())
        self.task.progress.completedUnitCount = min(99, max(0, completed))
      }
    }
  }

  func finish(success: Bool) {
    runOnMain { [weak self] in
      guard let self else { return }
      self.progressTimer?.invalidate()
      self.progressTimer = nil
      if success {
        self.task.progress.completedUnitCount = 100
      }
      self.task.setTaskCompleted(success: success)
    }
  }

  private func expire() {
    runOnMain { [weak self] in
      guard let self else { return }
      self.expired = true
      self.progressTimer?.invalidate()
      self.progressTimer = nil
      self.exporter?.cancelExport()
    }
  }

  private func runOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }
}

@available(iOS 26.0, *)
private final class ContinuedVideoExportCoordinator {
  static let shared = ContinuedVideoExportCoordinator()

  private let identifier = "\(Bundle.main.bundleIdentifier ?? "io.github.finngrndl.aquarecover").video-export"
  private var registered = false
  private var pendingWork: ((VideoExportActivity) -> Void)?

  func register() {
    guard !registered else { return }
    registered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier,
      using: .main
    ) { [weak self] task in
      guard let self, let task = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      guard let work = self.pendingWork else {
        task.setTaskCompleted(success: false)
        return
      }
      self.pendingWork = nil
      work(ContinuedVideoExportActivity(task: task))
    }
  }

  func submit(work: @escaping (VideoExportActivity) -> Void) -> Bool {
    guard registered, pendingWork == nil else { return false }
    pendingWork = work
    let request = BGContinuedProcessingTaskRequest(
      identifier: identifier,
      title: "Exporting video",
      subtitle: "AquaRecover is processing your video"
    )
    request.strategy = .fail
    do {
      try BGTaskScheduler.shared.submit(request)
      return true
    } catch {
      pendingWork = nil
      return false
    }
  }
}

/// Flutter channel glue for iOS. Rendering lives in AquaMediaPipeline.swift,
/// which the macOS runner shares through MacMediaProcessor.swift.
enum IosVideoProcessor {
  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let pipeline = AquaMediaPipeline()
    if #available(iOS 26.0, *) {
      ContinuedVideoExportCoordinator.shared.register()
    }
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
      let startExport: (VideoExportActivity) -> Void = { activity in
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            try pipeline.restoreVideo(
              inputPath: inputPath,
              outputPath: outputPath,
              args: args,
              onExporterReady: activity.attach
            ) { exportResult in
              DispatchQueue.main.async {
                switch exportResult {
                case .success(let path):
                  activity.finish(success: true)
                  result(path)
                case .failure(let error):
                  activity.finish(success: false)
                  result(flutterError(error, code: "VIDEO_EXPORT_FAILED"))
                }
              }
            }
          } catch {
            DispatchQueue.main.async {
              activity.finish(success: false)
              result(flutterError(error, code: "VIDEO_EXPORT_FAILED"))
            }
          }
        }
      }
      if #available(iOS 26.0, *),
         ContinuedVideoExportCoordinator.shared.submit(work: startExport) {
        return
      }
      startExport(BackgroundTaskLease(name: "AquaRecover video export"))
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

    let timeline = AquaTimelineRenderer(pipeline: pipeline)
    let timelineChannel = FlutterMethodChannel(name: "aqua_recover/timeline", binaryMessenger: binaryMessenger)
    timelineChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "cancelTimeline":
        timeline.cancel()
        result(nil)
      case "renderTimeline":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "BAD_ARGS", message: "Timeline arguments are required", details: nil))
          return
        }
        let lease = BackgroundTaskLease(name: "AquaRecover timeline export")
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let path = try timeline.render(args: args) { progress in
              DispatchQueue.main.async { timelineChannel.invokeMethod("progress", arguments: progress) }
            }
            DispatchQueue.main.async {
              lease.finish(success: true)
              result(path)
            }
          } catch {
            DispatchQueue.main.async {
              lease.finish(success: false)
              result(flutterError(error, code: "TIMELINE_RENDER_FAILED"))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func flutterError(_ error: Error, code: String) -> FlutterError {
    let resolvedCode = AquaMediaPipeline.isCancellation(error) ? "CANCELLED" : code
    return FlutterError(code: resolvedCode, message: error.localizedDescription, details: nil)
  }
}
