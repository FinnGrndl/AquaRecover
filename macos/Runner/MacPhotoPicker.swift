import AppKit
import FlutterMacOS
import Foundation
import PhotosUI
import UniformTypeIdentifiers

/// Presents the out-of-process system Photos picker on macOS 13 and later.
///
/// The picker runs in a separate process and only hands over the items the
/// user selects, so no Photos library permission prompt is required. Selected
/// originals are copied into the app container before the Flutter call returns
/// because the provider's temporary files are removed afterwards.
final class MacPhotoPicker: NSObject {
  private static let channelName = "aqua_recover/photo_picker"
  private static let importFolderName = "AquaRecover Photos Import"

  private weak var viewController: NSViewController?
  private var pendingResult: FlutterResult?
  private var activePicker: NSViewController?

  private init(viewController: NSViewController) {
    self.viewController = viewController
  }

  private static var instance: MacPhotoPicker?

  static func register(viewController: FlutterViewController) {
    let picker = MacPhotoPicker(viewController: viewController)
    instance = picker
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: viewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        if #available(macOS 13.0, *) {
          result(true)
        } else {
          result(false)
        }
      case "pickMedia":
        let args = call.arguments as? [String: Any] ?? [:]
        let limit = (args["selectionLimit"] as? NSNumber)?.intValue ?? 0
        picker.pickMedia(selectionLimit: max(0, limit), result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickMedia(selectionLimit: Int, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(
        FlutterError(
          code: "UNAVAILABLE",
          message: "The system Photos picker requires macOS 13 or later.",
          details: nil
        )
      )
      return
    }
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "BUSY",
          message: "A Photos selection is already open.",
          details: nil
        )
      )
      return
    }
    guard let host = viewController else {
      result(
        FlutterError(
          code: "NO_WINDOW",
          message: "AquaRecover has no window to present the Photos picker.",
          details: nil
        )
      )
      return
    }

    var configuration = PHPickerConfiguration()
    configuration.selectionLimit = selectionLimit
    configuration.filter = PHPickerFilter.any(of: [.images, .videos, .livePhotos])
    configuration.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    pendingResult = result
    activePicker = picker
    // A sheet takes the size its controller asks for, and the picker asks for
    // almost nothing, so size it to the window like the Photos app's own sheet.
    let bounds = host.view.bounds.size
    let size = NSSize(
      width: min(max(bounds.width - 80, 640), 1100),
      height: min(max(bounds.height - 80, 480), 800)
    )
    picker.preferredContentSize = size
    picker.view.setFrameSize(size)
    host.presentAsSheet(picker)
  }

  @available(macOS 13.0, *)
  fileprivate func finish(with results: [PHPickerResult]) {
    if let picker = activePicker {
      picker.presentingViewController?.dismiss(picker)
    }
    activePicker = nil
    guard let result = pendingResult else { return }
    pendingResult = nil
    guard !results.isEmpty else {
      result([String]())
      return
    }

    let destination: URL
    do {
      destination = try Self.makeImportDirectory()
    } catch {
      result(
        FlutterError(
          code: "IMPORT_FAILED",
          message: "Could not prepare a folder for the selected Photos items.",
          details: error.localizedDescription
        )
      )
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var paths = [String?](repeating: nil, count: results.count)
    var failures = 0

    for (index, item) in results.enumerated() {
      let provider = item.itemProvider
      guard let typeIdentifier = Self.preferredTypeIdentifier(for: provider) else {
        lock.lock()
        failures += 1
        lock.unlock()
        continue
      }
      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
        defer { group.leave() }
        guard let url else {
          lock.lock()
          failures += 1
          lock.unlock()
          return
        }
        do {
          let copied = try Self.copyToImportDirectory(
            url,
            destination: destination,
            index: index,
            suggestedName: provider.suggestedName,
            typeIdentifier: typeIdentifier
          )
          lock.lock()
          paths[index] = copied.path
          lock.unlock()
        } catch {
          lock.lock()
          failures += 1
          lock.unlock()
        }
      }
    }

    group.notify(queue: .main) {
      let imported = paths.compactMap { $0 }
      if imported.isEmpty && failures > 0 {
        result(
          FlutterError(
            code: "IMPORT_FAILED",
            message: "The selected Photos items could not be copied. If they are stored in iCloud, open them in Photos to download the originals, then try again.",
            details: nil
          )
        )
        return
      }
      result(["paths": imported, "failures": failures])
    }
  }

  /// Picks the most useful representation: RAW originals first, then other
  /// still images, then movies. Live Photos therefore import as their still.
  @available(macOS 13.0, *)
  private static func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
    let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
    if let raw = types.first(where: { $0.conforms(to: .rawImage) }) {
      return raw.identifier
    }
    if let image = types.first(where: { $0.conforms(to: .image) && $0 != .livePhoto }) {
      return image.identifier
    }
    if let movie = types.first(where: { $0.conforms(to: .movie) }) {
      return movie.identifier
    }
    return nil
  }

  private static func makeImportDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(importFolderName, isDirectory: true)
    let session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    return session
  }

  @available(macOS 13.0, *)
  private static func copyToImportDirectory(
    _ source: URL,
    destination: URL,
    index: Int,
    suggestedName: String?,
    typeIdentifier: String
  ) throws -> URL {
    let sourceExtension = source.pathExtension
    let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat"
    let fileExtension = sourceExtension.isEmpty ? fallbackExtension : sourceExtension
    let rawBase = suggestedName.flatMap { $0.isEmpty ? nil : $0 }
      ?? source.deletingPathExtension().lastPathComponent
    let base = sanitize(rawBase)
    let fileName = String(format: "%03d-%@.%@", index + 1, base, fileExtension.lowercased())
    let target = destination.appendingPathComponent(fileName, isDirectory: false)
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.copyItem(at: source, to: target)
    return target
  }

  private static func sanitize(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
    if cleaned.isEmpty { return "Photo" }
    return String(cleaned.prefix(80))
  }
}

@available(macOS 13.0, *)
extension MacPhotoPicker: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    finish(with: results)
  }
}
