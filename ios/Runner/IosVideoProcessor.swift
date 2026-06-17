import AVFoundation
import CoreImage
import Flutter
import Foundation

final class IosVideoProcessor {
  private let context = CIContext(options: [
    .workingColorSpace: NSNull(),
    .outputColorSpace: NSNull(),
  ])

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let processor = IosVideoProcessor()
    let channel = FlutterMethodChannel(name: "aqua_recover/video", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { call, result in
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

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try processor.restoreVideo(inputPath: inputPath, outputPath: outputPath, args: args) { exportResult in
            DispatchQueue.main.async {
              switch exportResult {
              case .success(let path):
                result(path)
              case .failure(let error):
                result(FlutterError(code: "VIDEO_EXPORT_FAILED", message: error.localizedDescription, details: nil))
              }
            }
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "VIDEO_EXPORT_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func restoreVideo(
    inputPath: String,
    outputPath: String,
    args: [String: Any],
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
        lut: lut
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
    guard exporter.supportedFileTypes.contains(.mp4) else {
      throw bridgeError("This device cannot export the selected video as MP4.")
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.videoComposition = videoComposition
    exporter.shouldOptimizeForNetworkUse = true
    if exportOptions.stripMetadata {
      exporter.metadata = []
    }

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

  private func applyFilters(
    to image: CIImage,
    extent: CGRect,
    settings: VideoSettings,
    lut: LutSettings
  ) -> CIImage {
    var output = image
    let safeRecovery = clamp(settings.recovery, 0.0, 1.5)
    let red = clamp(0.040 * safeRecovery * settings.redRecovery, -0.18, 0.18)
    let blueTrim = clamp(-0.018 * safeRecovery, -0.12, 0.0)
    let greenTrim = clamp(-0.014 * settings.hazeReduction, -0.14, 0.0)

    output = colorMatrix(
      image: output,
      extent: extent,
      redGain: 1.0 + red * 1.50,
      greenGain: 1.0 + greenTrim,
      blueGain: 1.0 + blueTrim * 0.85,
      redBias: red * 0.030,
      greenBias: greenTrim * 0.010,
      blueBias: blueTrim * 0.008
    )

    let saturation = max(0.1, 1.0 + (settings.saturation - 1.0) * 0.65 + settings.vibrance * 0.10)
    let contrast = max(0.1, 1.0 + (settings.contrast - 1.0) * 0.85 + settings.hazeReduction * 0.05)
    let brightness = clamp(
      0.006 + settings.brightness * 0.20 + settings.exposure * 0.09 + settings.shadows * 0.030 + settings.highlights * 0.018 - settings.blackPoint * 0.070,
      -1.0,
      1.0
    )
    if let filter = CIFilter(name: "CIColorControls") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(saturation, forKey: kCIInputSaturationKey)
      filter.setValue(contrast, forKey: kCIInputContrastKey)
      filter.setValue(brightness, forKey: kCIInputBrightnessKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    if abs(settings.exposure) > 0.001, let filter = CIFilter(name: "CIExposureAdjust") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.exposure * 0.35, forKey: kCIInputEVKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    if abs(settings.gamma - 1.0) > 0.001, let filter = CIFilter(name: "CIGammaAdjust") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(clamp(settings.gamma, 0.1, 3.0), forKey: "inputPower")
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    if abs(settings.hue) > 0.0001, let filter = CIFilter(name: "CIHueAdjust") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.hue * Double.pi, forKey: kCIInputAngleKey)
      output = filter.outputImage?.cropped(to: extent) ?? output
    }

    if abs(settings.highlights) > 0.001 || abs(settings.shadows) > 0.001,
       let filter = CIFilter(name: "CIHighlightShadowAdjust") {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(clamp(1.0 + settings.shadows * 0.45, 0.0, 2.0), forKey: "inputShadowAmount")
      filter.setValue(clamp(1.0 - settings.highlights * 0.28, 0.0, 2.0), forKey: "inputHighlightAmount")
      output = filter.outputImage?.cropped(to: extent) ?? output
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

  private func bridgeError(_ message: String) -> NSError {
    NSError(domain: "AquaRecoverVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

private struct VideoSettings {
  init(_ values: [String: Any]) {
    recovery = double(values, key: "recovery", fallback: 1.18)
    redRecovery = double(values, key: "redRecovery", fallback: 1.24)
    contrast = double(values, key: "contrast", fallback: 1.04)
    gamma = double(values, key: "gamma", fallback: 0.98)
    saturation = double(values, key: "saturation", fallback: 0.88)
    vibrance = double(values, key: "vibrance", fallback: 0.06)
    clarity = double(values, key: "clarity", fallback: 0.18)
    sharpness = double(values, key: "sharpness", fallback: 0.18)
    hazeReduction = double(values, key: "hazeReduction", fallback: 0.14)
    hue = double(values, key: "hue", fallback: 0.0)
    brightness = double(values, key: "brightness", fallback: 0.0)
    exposure = double(values, key: "exposure", fallback: -0.04)
    highlights = double(values, key: "highlights", fallback: 0.0)
    shadows = double(values, key: "shadows", fallback: 0.0)
    blackPoint = double(values, key: "blackPoint", fallback: 0.0)
    vignette = double(values, key: "vignette", fallback: 0.0)
  }

  let recovery: Double
  let redRecovery: Double
  let contrast: Double
  let gamma: Double
  let saturation: Double
  let vibrance: Double
  let clarity: Double
  let sharpness: Double
  let hazeReduction: Double
  let hue: Double
  let brightness: Double
  let exposure: Double
  let highlights: Double
  let shadows: Double
  let blackPoint: Double
  let vignette: Double
}

private struct ExportSettings {
  init(_ values: [String: Any]) {
    keepAudio = bool(values, key: "keepAudio", fallback: true)
    stripMetadata = bool(values, key: "stripMetadata", fallback: true)
  }

  let keepAudio: Bool
  let stripMetadata: Bool
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
