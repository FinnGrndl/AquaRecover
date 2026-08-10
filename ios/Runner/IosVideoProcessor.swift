import AVFoundation
import BackgroundTasks
import CoreImage
import Flutter
import Foundation
import ImageIO
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

final class IosVideoProcessor {
  private static let maxImagePixels: CGFloat = 120_000_000
  private static let maxImageDimension: CGFloat = 16_384

  private static let baseRecoveryKernel = CIColorKernel(source: """
    kernel vec4 aquaBaseRecovery(
      __sample original,
      float meanR,
      float meanG,
      float meanB,
      float recovery,
      float redRecovery,
      float autoWhiteBalance,
      float contrastStretch,
      float contrast,
      float gamma,
      float saturation,
      float vibrance,
      float hazeReduction,
      float highlightProtection,
      float brightness,
      float exposure,
      float highlights,
      float shadows,
      float blackPoint,
      float lowMidLuma
    ) {
      float originalR = clamp(original.r, 0.0, 1.0);
      float originalG = clamp(original.g, 0.0, 1.0);
      float originalB = clamp(original.b, 0.0, 1.0);
      float blueGreen = max(originalG, originalB);
      float redDeficit = blueGreen <= 0.004 ? 0.0 : clamp((blueGreen - originalR) / 0.6470588, 0.0, 1.0);
      float blueDominance = clamp((originalB - originalR) / 0.7058824, 0.0, 1.0);
      float greenDominance = clamp((originalG - originalR) / 0.7058824, 0.0, 1.0);
      float maxOriginal = max(originalR, max(originalG, originalB));
      float minOriginal = min(originalR, min(originalG, originalB));
      float chroma = clamp((maxOriginal - minOriginal) / 0.5490196, 0.0, 1.0);
      float openWater = clamp(redDeficit * (0.58 * blueDominance + 0.42 * greenDominance) * chroma, 0.0, 1.0);

      float grayMean = (meanR + meanG + meanB) / 3.0;
      float redGreenRatio = meanR / max(0.004, meanG);
      float blueGreenRatio = meanB / max(0.004, meanG);
      float severeRedLoss = 1.0 - step(0.12, redGreenRatio);
      float blueNotDominant = severeRedLoss * (1.0 - step(meanG * 1.12, meanB));
      float rGain = mix(1.0, clamp(grayMean / max(0.004, meanR), 0.75, 2.05), clamp(autoWhiteBalance, 0.0, 1.0));
      float gGain = mix(1.0, clamp(grayMean / max(0.004, meanG), 0.82, 1.28), clamp(autoWhiteBalance * 0.45, 0.0, 1.0));
      float bGainMin = mix(0.58, 0.90, blueNotDominant);
      float bGainWeight = clamp(autoWhiteBalance * mix(0.62, 0.26, blueNotDominant), 0.0, 1.0);
      float bGain = mix(1.0, clamp(grayMean / max(0.004, meanB), bGainMin, 1.14), bGainWeight);

      float r = originalR;
      float g = originalG;
      float b = originalB;
      float correctionScale = clamp(recovery / 1.18, 0.0, 1.2711864);
      float highlightWeight = 1.0 - clamp(highlightProtection, 0.0, 1.0) * pow(maxOriginal, 2.0);
      float redLiftScale = mix(0.42, 0.18, openWater);
      r += clamp(recovery, 0.0, 1.5) * clamp(redRecovery, 0.0, 2.5) * redLiftScale * max(0.0, g - r) * (1.0 - r) * highlightWeight;
      b += clamp(recovery, 0.0, 1.5) * 0.10 * max(0.0, g - b) * (1.0 - b) * highlightWeight;

      float haze = min(g, b) * 0.08 * clamp(hazeReduction, 0.0, 1.0);
      r = max(0.0, r - haze * 0.25);
      g = max(0.0, g - haze);
      b = max(0.0, b - haze * 0.75);
      r *= rGain;
      g *= gGain;
      b *= bGain;

      float lumaNow = dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722));
      float redDeficitNow = max(0.0, max(g, b) - r);
      float brightSurface = clamp((dot(vec3(originalR, originalG, originalB), vec3(0.2126, 0.7152, 0.0722)) - 0.1647059) / 0.5176471, 0.0, 1.0);
      float notPureWater = clamp(1.0 - openWater * 0.52, 0.18, 1.0);
      float cyanMaterial = clamp(redDeficit * brightSurface * notPureWater, 0.0, 1.0);
      float neutralize = clamp(clamp(recovery, 0.0, 1.5) * (0.38 + clamp(redRecovery, 0.0, 2.5) * 0.16) * cyanMaterial, 0.0, 0.74);
      r = mix(r, max(r, lumaNow + redDeficitNow * 0.18), neutralize);
      g = mix(g, mix(g, lumaNow, 0.22), neutralize * 0.70);
      b = mix(b, mix(b, lumaNow, 0.18), neutralize * 0.56);

      float contrastFactor = max(0.1, clamp(contrast, 0.1, 3.0) * (1.0 + clamp(contrastStretch, 0.0, 1.0) * 0.08));
      r = (r - 0.5) * contrastFactor + 0.5;
      g = (g - 0.5) * contrastFactor + 0.5;
      b = (b - 0.5) * contrastFactor + 0.5;

      float invGamma = 1.0 / clamp(gamma, 0.1, 3.0);
      r = pow(clamp(r, 0.0, 1.0), invGamma);
      g = pow(clamp(g, 0.0, 1.0), invGamma);
      b = pow(clamp(b, 0.0, 1.0), invGamma);

      float maxChannel = max(r, max(g, b));
      float luma = dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722));
      float effectiveSat = clamp(saturation, 0.0, 3.0) * (1.0 + clamp(vibrance, 0.0, 1.0) * (1.0 - clamp(maxChannel, 0.0, 1.0)));
      effectiveSat = mix(effectiveSat, min(effectiveSat, 0.96), openWater * 0.72 * correctionScale);
      r = luma + (r - luma) * effectiveSat;
      g = luma + (g - luma) * effectiveSat;
      b = luma + (b - luma) * effectiveSat;

      float tone = clamp(dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
      float shadowsLift = clamp(shadows, -1.0, 1.0) * 0.3529412 * pow(1.0 - tone, 2.0);
      float highlightsLift = clamp(highlights, -1.0, 1.0) * 0.3529412 * pow(tone, 2.0);
      float blackOffset = clamp(blackPoint, 0.0, 1.0) * 0.4705882;
      float exposureGain = pow(2.0, clamp(exposure, -1.0, 1.0));
      float brightnessOffset = clamp(brightness, -1.0, 1.0) * 0.2745098;
      r = (r + shadowsLift + highlightsLift - blackOffset) * exposureGain + brightnessOffset;
      g = (g + shadowsLift + highlightsLift - blackOffset) * exposureGain + brightnessOffset;
      b = (b + shadowsLift + highlightsLift - blackOffset) * exposureGain + brightnessOffset;

      float darkBlueSceneLift = clamp((0.2156863 - lowMidLuma) / 0.1176471, 0.0, 1.0) * clamp((blueGreenRatio - 1.25) / 0.20, 0.0, 1.0) * clamp((0.14 - redGreenRatio) / 0.14, 0.0, 1.0) * correctionScale;
      float darkTone = clamp(dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
      float darkLift = darkBlueSceneLift * (0.0705882 + 0.4941176 * pow(darkTone, 1.42));
      r += darkLift * 1.20;
      g += darkLift * 1.04;
      b += darkLift * 0.88;

      float shallowLift = blueNotDominant * (1.0 - step(0.3215686, lowMidLuma)) * 0.0392157 * pow(clamp(dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0), 2.2) * correctionScale;
      r += shallowLift * 1.04;
      g += shallowLift;
      b += shallowLift;
      float shallowWaterLiftScene = blueNotDominant * clamp((0.3215686 - lowMidLuma) / 0.1176471, 0.0, 1.0) * clamp((1.20 - blueGreenRatio) / 0.25, 0.0, 1.0) * correctionScale;
      float waterTone = clamp(dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
      float waterLift = shallowWaterLiftScene * openWater * (0.0274510 + 0.1098039 * pow(1.0 - waterTone, 1.25));
      r += waterLift * 0.52;
      g += waterLift * 0.90;
      b += waterLift * 1.18;

      float brightShallowDim = blueNotDominant * clamp((lowMidLuma - 0.2980392) / 0.1411765, 0.0, 1.0) * clamp((1.20 - blueGreenRatio) / 0.25, 0.0, 1.0) * correctionScale;
      float dimTone = clamp(dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
      float dim = brightShallowDim * (0.1333333 + 0.2274510 * pow(dimTone, 1.25));
      r -= dim * 1.08;
      g -= dim;
      b -= dim * 0.86;

      float surfaceMask = 1.0 - step(originalG * 1.12, originalB);
      float surfaceRedTarget = min(g, b) * 0.94;
      float inputRedLoss = clamp((min(originalG, originalB) - originalR) / 0.5098039, 0.0, 1.0);
      float neutralWeight = clamp((0.18 + inputRedLoss * 0.62) * (1.0 - openWater * 0.25), 0.0, 0.82) * correctionScale;
      r = mix(r, max(r, surfaceRedTarget), surfaceMask * neutralWeight);

      float shallowChromaLuma = dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722));
      float shallowChromaBoost = 1.0 + brightShallowDim * 0.62;
      r = shallowChromaLuma + (r - shallowChromaLuma) * shallowChromaBoost;
      g = shallowChromaLuma + (g - shallowChromaLuma) * shallowChromaBoost;
      b = shallowChromaLuma + (b - shallowChromaLuma) * shallowChromaBoost;

      float materialWarm = clamp(brightShallowDim * cyanMaterial * (1.0 - openWater * 0.55), 0.0, 1.0);
      r *= 1.0 + materialWarm * 0.72;
      g *= 1.0 + materialWarm * 0.08;
      b *= 1.0 - materialWarm * 0.44;
      float warmedLuma = dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722));
      float warmScale = shallowChromaLuma / max(0.004, warmedLuma);
      r *= warmScale;
      g *= warmScale;
      b *= warmScale;

      float pureWaterCeiling = mix(1.32, 0.74, openWater);
      float materialCeiling = mix(pureWaterCeiling, 1.05, cyanMaterial * 0.92);
      float redCeiling = max(g, b) * materialCeiling + 0.0470588;
      r = mix(r, min(r, redCeiling), openWater * 0.78 * correctionScale);

      return vec4(clamp(vec3(r, g, b), vec3(0.0), vec3(1.0)), original.a);
    }
  """)

  private static let retinexFusionKernel = CIColorKernel(source: """
    kernel vec4 aquaRetinexFusion(
      __sample original,
      __sample current,
      __sample smallBlur,
      __sample mediumBlur,
      __sample largeBlur,
      __sample localRgb,
      float redGreenRatio,
      float blueGreenRatio,
      float recovery
    ) {
      float originalR = clamp(original.r, 0.0, 1.0);
      float originalG = clamp(original.g, 0.0, 1.0);
      float originalB = clamp(original.b, 0.0, 1.0);
      float openBlueGreen = max(originalG, originalB);
      float redDeficit = openBlueGreen <= 0.004 ? 0.0 : clamp((openBlueGreen - originalR) / 0.6470588, 0.0, 1.0);
      float blueDominance = clamp((originalB - originalR) / 0.7058824, 0.0, 1.0);
      float greenDominance = clamp((originalG - originalR) / 0.7058824, 0.0, 1.0);
      float maxOriginal = max(originalR, max(originalG, originalB));
      float minOriginal = min(originalR, min(originalG, originalB));
      float chroma = clamp((maxOriginal - minOriginal) / 0.5490196, 0.0, 1.0);
      float openWater = clamp(redDeficit * (0.58 * blueDominance + 0.42 * greenDominance) * chroma, 0.0, 1.0);

      float luma = dot(current.rgb, vec3(0.2126, 0.7152, 0.0722));
      float smallLuma = dot(smallBlur.rgb, vec3(0.2126, 0.7152, 0.0722));
      float mediumLuma = dot(mediumBlur.rgb, vec3(0.2126, 0.7152, 0.0722));
      float largeLuma = dot(largeBlur.rgb, vec3(0.2126, 0.7152, 0.0722));
      float smallDetail = luma - smallLuma;
      float mediumDetail = luma - mediumLuma;
      float largeDetail = luma - largeLuma;
      float localContrast = clamp(smallDetail * 0.12 + mediumDetail * 0.32 + largeDetail * 0.56, -0.45, 0.45);
      float texture = clamp(abs(smallDetail) * 5.5 + abs(mediumDetail) * 3.0, 0.0, 1.0);

      float blueScene = clamp((blueGreenRatio - 1.08) / 0.34, 0.0, 1.0);
      float redLossScene = clamp((0.22 - redGreenRatio) / 0.20, 0.0, 1.0);
      float waterSuppression = 1.0 - openWater * mix(0.88, 0.28, texture);
      float material = clamp(redDeficit * (0.14 + texture * 1.72) * waterSuppression * mix(0.38, 1.0, redLossScene), 0.0, 1.0);
      if (material <= 0.002 && abs(localContrast) <= 0.01) {
        return current;
      }

      float localTone = localContrast * (18.0 + 42.0 * material) / 255.0 * (1.0 - openWater * 0.45);
      float hazeLift = material * clamp(1.0 - luma, 0.0, 1.0) * mix(0.2, 13.0, max(blueScene, redLossScene * 0.35)) / 255.0;
      float targetLuma = clamp(luma + localTone + hazeLift, 0.0, 1.0);
      float targetRg = mix(1.00, 0.96, blueScene);
      float targetBg = mix(0.96, 1.02, blueScene);
      float targetG = targetLuma / max(0.001, 0.2126 * targetRg + 0.7152 + 0.0722 * targetBg);
      vec3 target = vec3(targetG * targetRg, targetG, targetG * targetBg);

      float localGray = (localRgb.r + localRgb.g + localRgb.b) / 3.0;
      float retinexPower = mix(0.52, 0.72, blueScene) * (0.82 + clamp(recovery, 0.0, 1.5) * 0.12);
      vec3 retinex;
      retinex.r = current.r * pow(clamp(localGray / max(0.012, localRgb.r), 0.72, 1.52), retinexPower);
      retinex.g = current.g * pow(clamp(localGray / max(0.012, localRgb.g), 0.78, 1.28), retinexPower * 0.82);
      retinex.b = current.b * pow(clamp(localGray / max(0.012, localRgb.b), 0.68, 1.24), retinexPower);
      float warmBias = clamp(material * (0.32 + texture * 0.68) * mix(0.48, 1.0, redLossScene), 0.0, 1.0);
      retinex.r *= 1.0 + warmBias * mix(0.08, 0.13, blueScene);
      retinex.g *= 1.0 - warmBias * 0.015;
      retinex.b *= 1.0 - warmBias * mix(0.04, 0.08, blueScene);
      float retinexLuma = dot(retinex, vec3(0.2126, 0.7152, 0.0722));
      if (retinexLuma > 0.004) {
        retinex *= targetLuma / retinexLuma;
      }

      vec3 fusedTarget = mix(target, retinex, 0.68);
      float amount = clamp(0.46 + clamp(recovery, 0.0, 1.5) * 0.28, 0.0, 0.88);
      float chromaWeight = clamp(material * amount * (0.56 + texture * 0.44), 0.0, 0.66);
      float lumaWeight = clamp((material * 0.24 + texture * 0.10) * (1.0 - openWater * 0.55), 0.0, 0.32);
      vec3 rgb = mix(current.rgb, fusedTarget, chromaWeight);
      float adjustedLuma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
      if (adjustedLuma > 0.004) {
        rgb *= mix(1.0, targetLuma / adjustedLuma, lumaWeight);
      }
      float brightSandWarm = clamp(blueScene * redLossScene * redDeficit * (1.0 - texture * 0.28) * (1.0 - openWater * 0.32) * clamp((luma - 0.42) / 0.34, 0.0, 1.0), 0.0, 1.0);
      float blueMaterialWarm = clamp(
        blueScene * redLossScene * redDeficit * (0.20 + texture * 0.62) * (1.0 - openWater * 0.72) * clamp((luma - 0.18) / 0.54, 0.0, 1.0) +
        brightSandWarm * 0.24,
        0.0,
        1.0
      );
      float preserveLuma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
      rgb.r *= 1.0 + blueMaterialWarm * 0.46;
      rgb.g *= 1.0 + blueMaterialWarm * 0.07;
      rgb.b *= 1.0 - blueMaterialWarm * 0.32;
      float blueWarmLuma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
      if (blueWarmLuma > 0.004) {
        rgb *= preserveLuma / blueWarmLuma;
      }
      return vec4(clamp(rgb, vec3(0.0), vec3(1.0)), current.a);
    }
  """)

  private let context = CIContext(options: [
    .workingColorSpace: NSNull(),
    .outputColorSpace: NSNull(),
  ])

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let processor = IosVideoProcessor()
    if #available(iOS 26.0, *) {
      ContinuedVideoExportCoordinator.shared.register()
    }
    let videoChannel = FlutterMethodChannel(name: "aqua_recover/video", binaryMessenger: binaryMessenger)
    videoChannel.setMethodCallHandler { call, result in
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
            try processor.restoreVideo(
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
                  result(FlutterError(code: "VIDEO_EXPORT_FAILED", message: error.localizedDescription, details: nil))
                }
              }
            }
          } catch {
            DispatchQueue.main.async {
              activity.finish(success: false)
              result(FlutterError(code: "VIDEO_EXPORT_FAILED", message: error.localizedDescription, details: nil))
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
          let restored = try processor.restoreImage(inputPath: inputPath, outputPath: outputPath, args: args)
          DispatchQueue.main.async { result(restored) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "IMAGE_RESTORE_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func restoreVideo(
    inputPath: String,
    outputPath: String,
    args: [String: Any],
    onExporterReady: @escaping (AVAssetExportSession) -> Void,
    completion: @escaping (Result<String, Error>) -> Void
  ) throws {
    let inputURL = try checkedInputURL(inputPath)
    let outputURL = try checkedOutputURL(outputPath)
    let asset = AVURLAsset(url: inputURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let sourceVideo = asset.tracks(withMediaType: .video).first else {
      throw bridgeError("The selected file does not contain a video track.")
    }

    let trim = args["trim"] as? [String: Any] ?? [:]
    let timeRange = try exportTimeRange(asset: asset, trim: trim)
    let settings = VideoSettings(args["settings"] as? [String: Any] ?? [:])
    let exportOptions = ExportSettings(args["exportOptions"] as? [String: Any] ?? [:])
    let lut = LutSettings(args["lutProfile"] as? [String: Any] ?? [:])
    guard lut.kind != "customCube" else {
      throw bridgeError("Custom .cube LUTs are not supported for native iOS video export.")
    }
    let sceneStats = estimateSceneStats(asset: asset, timeRange: timeRange)

    let composition = AVMutableComposition()
    guard let videoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw bridgeError("Could not create the export video track.")
    }
    try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: .zero)
    videoTrack.preferredTransform = sourceVideo.preferredTransform

    if exportOptions.keepAudio {
      for sourceAudio in asset.tracks(withMediaType: .audio) {
        guard let audioTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
          continue
        }
        try audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: .zero)
      }
    }

    let videoComposition = AVVideoComposition(asset: composition) { [weak self] request in
      guard let self = self else {
        request.finish(with: request.sourceImage, context: nil)
        return
      }
      let extent = request.sourceImage.extent
      let filtered = self.applyFilters(
        to: request.sourceImage,
        extent: extent,
        settings: settings,
        lut: lut,
        sceneStats: sceneStats
      )
      request.finish(with: filtered.cropped(to: extent), context: self.context)
    }

    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    guard let exporter = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw bridgeError("Could not create an AVFoundation export session.")
    }
    let outputFileType: AVFileType = exportOptions.videoFormat == "mov" ? .mov : .mp4
    guard exporter.supportedFileTypes.contains(outputFileType) else {
      throw bridgeError(
        "This device cannot export the selected video as \(exportOptions.videoFormat.uppercased())."
      )
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = outputFileType
    exporter.videoComposition = videoComposition
    exporter.shouldOptimizeForNetworkUse = true
    if exportOptions.stripMetadata {
      exporter.metadata = []
    }
    onExporterReady(exporter)

    exporter.exportAsynchronously {
      switch exporter.status {
      case .completed:
        completion(.success(outputURL.path))
      case .failed:
        completion(.failure(exporter.error ?? self.bridgeError("AVFoundation video export failed.")))
      case .cancelled:
        completion(.failure(self.bridgeError("AVFoundation video export was cancelled.")))
      default:
        completion(.failure(self.bridgeError("AVFoundation video export ended unexpectedly.")))
      }
    }
  }

  private func restoreImage(inputPath: String, outputPath: String, args: [String: Any]) throws -> String {
    try autoreleasepool {
      let inputURL = try checkedInputURL(inputPath)
      let outputURL = try checkedOutputURL(outputPath)
      let settings = VideoSettings(args["settings"] as? [String: Any] ?? [:])
      let exportOptions = ExportSettings(args["exportOptions"] as? [String: Any] ?? [:])
      let lut = LutSettings(args["lutProfile"] as? [String: Any] ?? [:])
      let transform = ImageTransformSettings(args["transform"] as? [String: Any] ?? [:])
      guard lut.kind != "customCube" else {
        throw bridgeError("Custom .cube LUTs are not supported for native iOS image export.")
      }
      guard let image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
        throw bridgeError("Could not load image with the platform decoder.")
      }

      let sourceExtent = image.extent.integral
      let requestedMaxDimension = double(args, key: "maxDimension", fallback: 0.0)
      if requestedMaxDimension <= 0.0 {
        try validateImageExtent(sourceExtent)
      }
      var source = image
        .cropped(to: sourceExtent)
        .transformed(by: CGAffineTransform(translationX: -sourceExtent.origin.x, y: -sourceExtent.origin.y))
      if requestedMaxDimension > 0.0 {
        let maxDimension = clamp(requestedMaxDimension, 64.0, Self.maxImageDimension)
        let maxSide = max(source.extent.width, source.extent.height)
        if maxSide > maxDimension {
          let scale = maxDimension / maxSide
          source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
      }
      let extent = source.extent.integral
      try validateImageExtent(extent)
      let sceneStats = estimateSceneStats(image: source, extent: extent)
      let restored = applyFilters(
        to: source,
        extent: extent,
        settings: settings,
        lut: lut,
        sceneStats: sceneStats
      ).cropped(to: extent)
      let transformed = applyImageTransform(to: restored, settings: transform)

      try writeImage(transformed, outputURL: outputURL, exportOptions: exportOptions, settings: settings)
      return outputURL.path
    }
  }

  private func applyImageTransform(
    to image: CIImage,
    settings: ImageTransformSettings
  ) -> CIImage {
    if settings.isIdentity { return image }
    var output = image
    switch settings.normalizedQuarterTurns {
    case 1:
      output = output.oriented(.right)
    case 2:
      output = output.oriented(.down)
    case 3:
      output = output.oriented(.left)
    default:
      break
    }
    if settings.flipHorizontal {
      output = output.oriented(.upMirrored)
    }
    if settings.flipVertical {
      output = output.oriented(.downMirrored)
    }
    output = output.transformed(
      by: CGAffineTransform(
        translationX: -output.extent.origin.x,
        y: -output.extent.origin.y
      )
    )
    let sourceWidth = output.extent.width
    let sourceHeight = output.extent.height
    if abs(settings.straightenDegrees) > 0.0000001 {
      let radians = CGFloat(-settings.straightenDegrees * Double.pi / 180.0)
      output = output.transformed(by: CGAffineTransform(rotationAngle: radians))
      output = output.transformed(
        by: CGAffineTransform(
          translationX: -output.extent.origin.x,
          y: -output.extent.origin.y
        )
      )
    }
    let extent = output.extent.integral
    let crop = settings.cropRect(
      outputWidth: extent.width,
      outputHeight: extent.height,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight
    )
    let coreImageCrop = CGRect(
      x: crop.origin.x,
      y: extent.height - crop.origin.y - crop.height,
      width: crop.width,
      height: crop.height
    ).integral.intersection(extent)
    let cropped = output.cropped(to: coreImageCrop)
    return cropped.transformed(
      by: CGAffineTransform(
        translationX: -cropped.extent.origin.x,
        y: -cropped.extent.origin.y
      )
    )
  }

  private func applyFilters(
    to image: CIImage,
    extent: CGRect,
    settings: VideoSettings,
    lut: LutSettings,
    sceneStats: VideoSceneStats
  ) -> CIImage {
    let original = image
    var output = image
    if !settings.isIdentity {
      output = applyBaseRecovery(
        to: image,
        extent: extent,
        settings: settings,
        sceneStats: sceneStats
      )
    }

    if abs(settings.hue) > 0.0001, let filter = CIFilter(name: "CIHueAdjust") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.hue * Double.pi, forKey: kCIInputAngleKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    if settings.recovery > 0.000001 {
      output = applyRetinexFusion(
        original: original,
        corrected: output,
        extent: extent,
        settings: settings,
        sceneStats: sceneStats
      )
    }

    output = applyBuiltInLut(output, extent: extent, lut: lut)

    let sharpness = clamp((settings.sharpness + settings.clarity * 0.65) * 0.70, 0.0, 1.5)
    if sharpness > 0.001, let filter = CIFilter(name: "CISharpenLuminance") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(sharpness, forKey: kCIInputSharpnessKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    if settings.vignette > 0.001, let filter = CIFilter(name: "CIVignette") {
      let radius = max(extent.width, extent.height) * 0.80
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.vignette * 0.85, forKey: kCIInputIntensityKey)
      filter.setValue(radius, forKey: kCIInputRadiusKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    return output
  }

  private func applyBaseRecovery(
    to image: CIImage,
    extent: CGRect,
    settings: VideoSettings,
    sceneStats: VideoSceneStats
  ) -> CIImage {
    guard let kernel = Self.baseRecoveryKernel else { return image }
    return kernel.apply(
      extent: extent,
      arguments: [
        image,
        sceneStats.meanRUnit,
        sceneStats.meanGUnit,
        sceneStats.meanBUnit,
        clamp(settings.recovery, 0.0, 1.5),
        clamp(settings.redRecovery, 0.0, 2.5),
        clamp(settings.autoWhiteBalance, 0.0, 1.0),
        clamp(settings.contrastStretch, 0.0, 1.0),
        clamp(settings.contrast, 0.1, 3.0),
        clamp(settings.gamma, 0.1, 3.0),
        clamp(settings.saturation, 0.0, 3.0),
        clamp(settings.vibrance, 0.0, 1.0),
        clamp(settings.hazeReduction, 0.0, 1.0),
        clamp(settings.highlightProtection, 0.0, 1.0),
        clamp(settings.brightness, -1.0, 1.0),
        clamp(settings.exposure, -1.0, 1.0),
        clamp(settings.highlights, -1.0, 1.0),
        clamp(settings.shadows, -1.0, 1.0),
        clamp(settings.blackPoint, 0.0, 1.0),
        sceneStats.lowMidLumaUnit,
      ]
    )?.cropped(to: extent) ?? image
  }

  private func applyRetinexFusion(
    original: CIImage,
    corrected: CIImage,
    extent: CGRect,
    settings: VideoSettings,
    sceneStats: VideoSceneStats
  ) -> CIImage {
    guard let kernel = Self.retinexFusionKernel else { return corrected }
    let shortSide = max(8.0, min(extent.width, extent.height))
    let smallBlur = blurred(corrected, extent: extent, radius: max(1.0, shortSide / 70.0))
    let mediumBlur = blurred(corrected, extent: extent, radius: max(2.0, shortSide / 36.0))
    let largeBlur = blurred(corrected, extent: extent, radius: max(3.0, shortSide / 18.0))
    return kernel.apply(
      extent: extent,
      arguments: [
        original,
        corrected,
        smallBlur,
        mediumBlur,
        largeBlur,
        largeBlur,
        sceneStats.redGreenRatio,
        sceneStats.blueGreenRatio,
        clamp(settings.recovery, 0.0, 1.5),
      ]
    )?.cropped(to: extent) ?? corrected
  }

  private func blurred(_ image: CIImage, extent: CGRect, radius: Double) -> CIImage {
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
    filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    return filter.outputImage?.cropped(to: extent) ?? image
  }

  private func estimateSceneStats(asset: AVAsset, timeRange: CMTimeRange) -> VideoSceneStats {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = false
    generator.maximumSize = CGSize(width: 256, height: 256)
    let midpoint = CMTimeAdd(
      timeRange.start,
      CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 0.5)
    )
    guard let cgImage = try? generator.copyCGImage(at: midpoint, actualTime: nil) else {
      return .fallback
    }
    return sceneStats(for: cgImage)
  }

  private func estimateSceneStats(image: CIImage, extent: CGRect) -> VideoSceneStats {
    let maxSide = max(extent.width, extent.height)
    guard maxSide.isFinite, maxSide > 0 else { return .fallback }
    let scale = maxSide > 256.0 ? 256.0 / maxSide : 1.0
    let sample = scale < 0.999
      ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      : image
    guard let cgImage = context.createCGImage(sample, from: sample.extent) else {
      return .fallback
    }
    return sceneStats(for: cgImage)
  }

  private func sceneStats(for cgImage: CGImage) -> VideoSceneStats {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0 && height > 0 else { return .fallback }
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
      CGBitmapInfo.byteOrder32Big.rawValue
    guard let bitmap = CGContext(
      data: &rgba,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo
    ) else {
      return .fallback
    }
    bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    var sumR = 0.0
    var sumG = 0.0
    var sumB = 0.0
    var lumaHistogram = [Int](repeating: 0, count: 256)
    let count = width * height
    for index in stride(from: 0, to: rgba.count, by: 4) {
      let r = Int(rgba[index])
      let g = Int(rgba[index + 1])
      let b = Int(rgba[index + 2])
      sumR += Double(r)
      sumG += Double(g)
      sumB += Double(b)
      let luma = min(
        255,
        max(0, Int((0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)).rounded()))
      )
      lumaHistogram[luma] += 1
    }
    return VideoSceneStats(
      meanR: sumR / Double(max(1, count)),
      meanG: sumG / Double(max(1, count)),
      meanB: sumB / Double(max(1, count)),
      lowMidLuma: percentile(lumaHistogram, total: count, percentile: 0.10)
    )
  }

  private func percentile(_ histogram: [Int], total: Int, percentile: Double) -> Double {
    let target = max(1, Int((Double(total) * percentile).rounded()))
    var running = 0
    for (index, count) in histogram.enumerated() {
      running += count
      if running >= target {
        return Double(index)
      }
    }
    return Double(histogram.count - 1)
  }

  private func applyBuiltInLut(_ image: CIImage, extent: CGRect, lut: LutSettings) -> CIImage {
    guard lut.intensity > 0.001 else { return image }
    switch lut.kind {
    case "coralWarm":
      return recipe(image: image, extent: extent, red: 1.08, green: 1.02, blue: 0.94, saturation: 1.08, contrast: 1.03, intensity: lut.intensity)
    case "blueWater":
      return recipe(image: image, extent: extent, red: 1.02, green: 1.01, blue: 1.05, saturation: 1.04, contrast: 1.05, intensity: lut.intensity)
    case "greenWater":
      return recipe(image: image, extent: extent, red: 1.10, green: 0.96, blue: 1.05, saturation: 1.06, contrast: 1.04, intensity: lut.intensity)
    default:
      return image
    }
  }

  private func recipe(
    image: CIImage,
    extent: CGRect,
    red: Double,
    green: Double,
    blue: Double,
    saturation: Double,
    contrast: Double,
    intensity: Double
  ) -> CIImage {
    let amount = clamp(intensity, 0.0, 1.0)
    var output = colorMatrix(
      image: image,
      extent: extent,
      redGain: 1.0 + (red - 1.0) * amount,
      greenGain: 1.0 + (green - 1.0) * amount,
      blueGain: 1.0 + (blue - 1.0) * amount,
      redBias: 0,
      greenBias: 0,
      blueBias: 0
    )
    if let filter = CIFilter(name: "CIColorControls") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(1.0 + (saturation - 1.0) * amount, forKey: kCIInputSaturationKey)
      filter.setValue(1.0 + (contrast - 1.0) * amount, forKey: kCIInputContrastKey)
      filter.setValue(0.0, forKey: kCIInputBrightnessKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }
    return output
  }

  private func colorMatrix(
    image: CIImage,
    extent: CGRect,
    redGain: Double,
    greenGain: Double,
    blueGain: Double,
    redBias: Double,
    greenBias: Double,
    blueBias: Double
  ) -> CIImage {
    guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(x: CGFloat(redGain), y: 0, z: 0, w: 0), forKey: "inputRVector")
    filter.setValue(CIVector(x: 0, y: CGFloat(greenGain), z: 0, w: 0), forKey: "inputGVector")
    filter.setValue(CIVector(x: 0, y: 0, z: CGFloat(blueGain), w: 0), forKey: "inputBVector")
    filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
    filter.setValue(CIVector(x: CGFloat(redBias), y: CGFloat(greenBias), z: CGFloat(blueBias), w: 0), forKey: "inputBiasVector")
    return filter.outputImage?.cropped(to: extent) ?? image
  }

  private func exportTimeRange(asset: AVAsset, trim: [String: Any]) throws -> CMTimeRange {
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration.isFinite, duration > 0 else {
      throw bridgeError("The video duration could not be read.")
    }
    let enabled = bool(trim, key: "enabled", fallback: false)
    let startSeconds = enabled ? max(0.0, double(trim, key: "startSeconds", fallback: 0.0)) : 0.0
    let requestedEnd = enabled ? optionalDouble(trim, key: "endSeconds") : nil
    let endSeconds = min(requestedEnd ?? duration, duration)
    guard startSeconds < endSeconds else {
      throw bridgeError("Trim start must be before the video end.")
    }
    let timescale = asset.duration.timescale == 0 ? CMTimeScale(600) : asset.duration.timescale
    let start = CMTime(seconds: startSeconds, preferredTimescale: timescale)
    let end = CMTime(seconds: endSeconds, preferredTimescale: timescale)
    return CMTimeRange(start: start, duration: end - start)
  }

  private func checkedInputURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.isFileURL else { throw bridgeError("Only local files are supported.") }
    guard FileManager.default.fileExists(atPath: url.path) else { throw bridgeError("Input file does not exist.") }
    return url
  }

  private func checkedOutputURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.isFileURL else { throw bridgeError("Only local output files are supported.") }
    return url
  }

  private func writeImage(
    _ image: CIImage,
    outputURL: URL,
    exportOptions: ExportSettings,
    settings: VideoSettings
  ) throws {
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw bridgeError("Could not create sRGB color space.")
    }

    let data: Data?
    if exportOptions.outputPng {
      data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace)
    } else {
      let qualityKey = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
      data = context.jpegRepresentation(
        of: image,
        colorSpace: colorSpace,
        options: [qualityKey: clamp(settings.jpegQuality / 100.0, 0.01, 1.0)]
      )
    }
    guard let rendered = data else {
      throw bridgeError("Could not render image export.")
    }
    try rendered.write(to: outputURL, options: .atomic)
  }

  private func validateImageExtent(_ extent: CGRect) throws {
    let width = abs(extent.width.rounded(.up))
    let height = abs(extent.height.rounded(.up))
    guard width.isFinite, height.isFinite, width > 0, height > 0 else {
      throw bridgeError("Decoded image dimensions are invalid.")
    }
    guard width <= Self.maxImageDimension, height <= Self.maxImageDimension else {
      throw bridgeError("Decoded image dimensions exceed the safe limit.")
    }
    guard width * height <= Self.maxImagePixels else {
      throw bridgeError("Decoded image is too large for local processing.")
    }
  }

  private func bridgeError(_ message: String) -> NSError {
    NSError(domain: "AquaRecoverVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

private struct VideoSceneStats {
  static let fallback = VideoSceneStats(meanR: 80.0, meanG: 112.0, meanB: 150.0, lowMidLuma: 55.0)

  init(meanR: Double, meanG: Double, meanB: Double, lowMidLuma: Double) {
    self.meanR = max(1.0, meanR)
    self.meanG = max(1.0, meanG)
    self.meanB = max(1.0, meanB)
    self.lowMidLuma = min(255.0, max(0.0, lowMidLuma))
  }

  let meanR: Double
  let meanG: Double
  let meanB: Double
  let lowMidLuma: Double

  var meanRUnit: Double { meanR / 255.0 }
  var meanGUnit: Double { meanG / 255.0 }
  var meanBUnit: Double { meanB / 255.0 }
  var lowMidLumaUnit: Double { lowMidLuma / 255.0 }
  var redGreenRatio: Double { meanR / max(1.0, meanG) }
  var blueGreenRatio: Double { meanB / max(1.0, meanG) }
}

private struct VideoSettings {
  init(_ values: [String: Any]) {
    recovery = double(values, key: "recovery", fallback: 1.18)
    redRecovery = double(values, key: "redRecovery", fallback: 1.24)
    autoWhiteBalance = double(values, key: "autoWhiteBalance", fallback: 0.76)
    contrastStretch = double(values, key: "contrastStretch", fallback: 0.52)
    contrast = double(values, key: "contrast", fallback: 1.04)
    gamma = double(values, key: "gamma", fallback: 0.98)
    saturation = double(values, key: "saturation", fallback: 0.88)
    vibrance = double(values, key: "vibrance", fallback: 0.06)
    clarity = double(values, key: "clarity", fallback: 0.18)
    sharpness = double(values, key: "sharpness", fallback: 0.18)
    hazeReduction = double(values, key: "hazeReduction", fallback: 0.14)
    highlightProtection = double(values, key: "highlightProtection", fallback: 0.55)
    hue = double(values, key: "hue", fallback: 0.0)
    brightness = double(values, key: "brightness", fallback: 0.0)
    exposure = double(values, key: "exposure", fallback: -0.04)
    highlights = double(values, key: "highlights", fallback: 0.0)
    shadows = double(values, key: "shadows", fallback: 0.0)
    blackPoint = double(values, key: "blackPoint", fallback: 0.0)
    vignette = double(values, key: "vignette", fallback: 0.0)
    jpegQuality = double(values, key: "jpegQuality", fallback: 94.0)
  }

  let recovery: Double
  let redRecovery: Double
  let autoWhiteBalance: Double
  let contrastStretch: Double
  let contrast: Double
  let gamma: Double
  let saturation: Double
  let vibrance: Double
  let clarity: Double
  let sharpness: Double
  let hazeReduction: Double
  let highlightProtection: Double
  let hue: Double
  let brightness: Double
  let exposure: Double
  let highlights: Double
  let shadows: Double
  let blackPoint: Double
  let vignette: Double
  let jpegQuality: Double

  var isIdentity: Bool {
    func same(_ lhs: Double, _ rhs: Double) -> Bool {
      abs(lhs - rhs) < 0.0000001
    }
    return same(recovery, 0.0)
      && same(redRecovery, 0.0)
      && same(autoWhiteBalance, 0.0)
      && same(contrastStretch, 0.0)
      && same(contrast, 1.0)
      && same(gamma, 1.0)
      && same(saturation, 1.0)
      && same(vibrance, 0.0)
      && same(clarity, 0.0)
      && same(sharpness, 0.0)
      && same(hazeReduction, 0.0)
      && same(highlightProtection, 0.0)
      && same(hue, 0.0)
      && same(brightness, 0.0)
      && same(exposure, 0.0)
      && same(highlights, 0.0)
      && same(shadows, 0.0)
      && same(blackPoint, 0.0)
      && same(vignette, 0.0)
  }
}

private struct ExportSettings {
  init(_ values: [String: Any]) {
    imageFormat = values["imageFormat"] as? String ?? "jpeg"
    videoFormat = values["videoFormat"] as? String ?? "mp4"
    keepAudio = bool(values, key: "keepAudio", fallback: true)
    stripMetadata = bool(values, key: "stripMetadata", fallback: true)
  }

  let imageFormat: String
  let videoFormat: String
  let keepAudio: Bool
  let stripMetadata: Bool

  var outputPng: Bool { imageFormat == "png" }
}

private struct ImageTransformSettings {
  init(_ values: [String: Any]) {
    aspectRatio = values["aspectRatio"] as? String ?? "original"
    zoom = double(values, key: "zoom", fallback: 1.0)
    offsetX = double(values, key: "offsetX", fallback: 0.0)
    offsetY = double(values, key: "offsetY", fallback: 0.0)
    quarterTurns = Int(double(values, key: "quarterTurns", fallback: 0.0))
    straightenDegrees = double(values, key: "straightenDegrees", fallback: 0.0)
    customAspectRatio = double(values, key: "customAspectRatio", fallback: 4.0 / 3.0)
    flipHorizontal = bool(values, key: "flipHorizontal", fallback: false)
    flipVertical = bool(values, key: "flipVertical", fallback: false)
  }

  let aspectRatio: String
  let zoom: Double
  let offsetX: Double
  let offsetY: Double
  let quarterTurns: Int
  let straightenDegrees: Double
  let customAspectRatio: Double
  let flipHorizontal: Bool
  let flipVertical: Bool

  var normalizedQuarterTurns: Int {
    ((quarterTurns % 4) + 4) % 4
  }

  var isIdentity: Bool {
    aspectRatio == "original"
      && abs(zoom - 1.0) < 0.0000001
      && abs(offsetX) < 0.0000001
      && abs(offsetY) < 0.0000001
      && normalizedQuarterTurns == 0
      && abs(straightenDegrees) < 0.0000001
      && !flipHorizontal
      && !flipVertical
  }

  func cropRect(
    outputWidth: CGFloat,
    outputHeight: CGFloat,
    sourceWidth: CGFloat,
    sourceHeight: CGFloat
  ) -> CGRect {
    let safeOutputWidth = max(1.0, outputWidth)
    let safeOutputHeight = max(1.0, outputHeight)
    let safeSourceWidth = max(1.0, sourceWidth)
    let safeSourceHeight = max(1.0, sourceHeight)
    let sourceAspect = safeSourceWidth / safeSourceHeight
    let portrait = sourceAspect < 1.0
    let targetAspect: CGFloat
    switch aspectRatio {
    case "freeform":
      targetAspect = CGFloat(clamp(customAspectRatio, 0.25, 4.0))
    case "square":
      targetAspect = 1.0
    case "fourThree":
      targetAspect = portrait ? 3.0 / 4.0 : 4.0 / 3.0
    case "sixteenNine":
      targetAspect = portrait ? 9.0 / 16.0 : 16.0 / 9.0
    default:
      targetAspect = sourceAspect
    }

    let radians = CGFloat(abs(straightenDegrees) * Double.pi / 180.0)
    let cosine = abs(cos(radians))
    let sine = abs(sin(radians))
    let rotationSafety: CGFloat = abs(straightenDegrees) > 0.0000001 ? 0.98 : 1.0
    let baseHeight = min(
      safeSourceWidth / (targetAspect * cosine + sine),
      safeSourceHeight / (targetAspect * sine + cosine)
    ) * rotationSafety
    let baseWidth = baseHeight * targetAspect
    let safeZoom = CGFloat(clamp(zoom, 1.0, 4.0))
    let cropWidth = max(1.0, min(safeOutputWidth, baseWidth / safeZoom))
    let cropHeight = max(1.0, min(safeOutputHeight, baseHeight / safeZoom))
    let baseLeft = (safeOutputWidth - baseWidth) / 2.0
    let baseTop = (safeOutputHeight - baseHeight) / 2.0
    let safeX = CGFloat(clamp(offsetX, -1.0, 1.0))
    let safeY = CGFloat(clamp(offsetY, -1.0, 1.0))
    let left = baseLeft + (baseWidth - cropWidth) * (safeX + 1.0) / 2.0
    let top = baseTop + (baseHeight - cropHeight) * (safeY + 1.0) / 2.0
    return CGRect(
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight
    )
  }
}

private struct LutSettings {
  init(_ values: [String: Any]) {
    kind = values["kind"] as? String ?? "none"
    intensity = double(values, key: "intensity", fallback: 0.0)
  }

  let kind: String
  let intensity: Double
}

private func double(_ values: [String: Any], key: String, fallback: Double) -> Double {
  if let number = values[key] as? NSNumber {
    return number.doubleValue
  }
  if let value = values[key] as? Double {
    return value
  }
  if let value = values[key] as? String, let parsed = Double(value) {
    return parsed
  }
  return fallback
}

private func optionalDouble(_ values: [String: Any], key: String) -> Double? {
  guard values[key] != nil else { return nil }
  return double(values, key: key, fallback: 0.0)
}

private func bool(_ values: [String: Any], key: String, fallback: Bool) -> Bool {
  if let value = values[key] as? Bool {
    return value
  }
  if let number = values[key] as? NSNumber {
    return number.boolValue
  }
  return fallback
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
  min(max(value, lower), upper)
}
