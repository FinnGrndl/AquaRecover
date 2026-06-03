import CoreImage
import CoreImage.CIFilterBuiltins
import Flutter
import Foundation

final class RawBridge {
  private static let maxDecodePixels: CGFloat = 120_000_000
  private static let maxDimension: CGFloat = 16_384

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "aqua_recover/raw", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "decodeRawToPng" || call.method == "decodeImageToPng" else {
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
          if call.method == "decodeRawToPng" {
            try renderRaw(inputPath: inputPath, outputPath: outputPath)
          } else {
            try renderPlatformImage(inputPath: inputPath, outputPath: outputPath)
          }
          DispatchQueue.main.async { result(outputPath) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "IMAGE_DECODE_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private static func renderRaw(inputPath: String, outputPath: String) throws {
    let inputURL = try checkedInputURL(inputPath)
    let outputURL = try checkedOutputURL(outputPath)
    var rendered: CIImage?

    if #available(iOS 15.0, *) {
      if let raw = CIRAWFilter(imageURL: inputURL) {
        raw.isGamutMappingEnabled = true
        raw.isLensCorrectionEnabled = true
        raw.luminanceNoiseReductionAmount = 0.12
        raw.localToneMapAmount = 0.25
        rendered = raw.outputImage
      }
    }

    if rendered == nil {
      rendered = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true])
    }

    guard let image = rendered else {
      throw bridgeError("Could not load RAW image.")
    }
    try writePng(image: image, outputURL: outputURL)
  }

  private static func renderPlatformImage(inputPath: String, outputPath: String) throws {
    let inputURL = try checkedInputURL(inputPath)
    let outputURL = try checkedOutputURL(outputPath)
    guard let image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
      throw bridgeError("Could not load image with the platform decoder.")
    }
    try writePng(image: image, outputURL: outputURL)
  }

  private static func writePng(image: CIImage, outputURL: URL) throws {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try validateExtent(image.extent)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw bridgeError("Could not create sRGB color space.")
    }

    var options: [CIContextOption: Any] = [:]
    if let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
      options[.workingColorSpace] = workingSpace
    }
    let context = CIContext(options: options)
    guard let data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) else {
      throw bridgeError("Could not render image as PNG.")
    }
    try data.write(to: outputURL, options: .atomic)
  }

  private static func checkedInputURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.isFileURL else { throw bridgeError("Only local files are supported.") }
    guard FileManager.default.fileExists(atPath: url.path) else { throw bridgeError("Input file does not exist.") }
    return url
  }

  private static func checkedOutputURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.isFileURL else { throw bridgeError("Only local output files are supported.") }
    return url
  }

  private static func validateExtent(_ extent: CGRect) throws {
    let width = abs(extent.width.rounded(.up))
    let height = abs(extent.height.rounded(.up))
    guard width.isFinite, height.isFinite, width > 0, height > 0 else {
      throw bridgeError("Decoded image dimensions are invalid.")
    }
    guard width <= maxDimension, height <= maxDimension else {
      throw bridgeError("Decoded image dimensions exceed the safe limit.")
    }
    guard width * height <= maxDecodePixels else {
      throw bridgeError("Decoded image is too large for local processing.")
    }
  }

  private static func bridgeError(_ message: String) -> NSError {
    NSError(domain: "AquaRecover", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
