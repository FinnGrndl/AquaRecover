import AVFoundation
import CoreImage
import Foundation

/// Renders an AquaRecover timeline (photos and clips, each with its own grade)
/// into one H.264 movie. Shared by the iOS and macOS runners; the Flutter glue
/// lives in IosVideoProcessor.swift and MacMediaProcessor.swift.
///
/// Every output frame is pulled through Core Image: video clips decode with
/// AVAssetReader, photos are graded once and cached, each frame gets the full
/// AquaMediaPipeline grade, crossfades blend two sources, and the result is
/// fitted into the output canvas and appended with AVAssetWriter. Clip audio
/// is mixed with AVAudioMix volume ramps and written alongside.
final class AquaTimelineRenderer {
  init(pipeline: AquaMediaPipeline) {
    self.pipeline = pipeline
  }

  private let pipeline: AquaMediaPipeline
  private let stateLock = NSLock()
  private var cancelled = false

  func cancel() {
    stateLock.lock()
    cancelled = true
    stateLock.unlock()
  }

  private var isCancelled: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return cancelled
  }

  /// Renders synchronously on the calling (background) thread.
  func render(args: [String: Any], progress: @escaping (Double) -> Void) throws -> String {
    stateLock.lock()
    cancelled = false
    stateLock.unlock()

    guard let outputPath = args["outputPath"] as? String,
          let rawClips = args["clips"] as? [[String: Any]], !rawClips.isEmpty else {
      throw pipeline.bridgeError("outputPath and at least one clip are required.")
    }
    let width = timelineInt(args["width"], fallback: 1920)
    let height = timelineInt(args["height"], fallback: 1080)
    let fps = Int32(timelineInt(args["frameRate"], fallback: 30))
    guard (16...8192).contains(width), (16...8192).contains(height), (12...60).contains(fps) else {
      throw pipeline.bridgeError("The timeline output size is out of range.")
    }
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    let clips = try rawClips.map { try TimelineClipSpec($0) }
    let duration = clips.map { $0.start + $0.duration }.max() ?? 0
    let totalFrames = Int((duration * Double(fps)).rounded(.up))
    guard totalFrames > 0 else { throw pipeline.bridgeError("The timeline is empty.") }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let bitrate = Double(width * height) * Double(fps) * 0.15
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Int(bitrate),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ],
    ])
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    guard writer.canAdd(videoInput) else {
      throw pipeline.bridgeError("Could not configure the timeline video encoder.")
    }
    writer.add(videoInput)

    let audio = try makeAudioMix(clips: clips)
    var audioInput: AVAssetWriterInput?
    if audio != nil {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
      ])
      input.expectsMediaDataInRealTime = false
      if writer.canAdd(input) {
        writer.add(input)
        audioInput = input
      }
    }

    guard writer.startWriting() else {
      throw writer.error ?? pipeline.bridgeError("Could not start the timeline writer.")
    }
    writer.startSession(atSourceTime: .zero)

    let audioDone = DispatchGroup()
    if let audio = audio, let audioInput = audioInput {
      audioDone.enter()
      let reader = audio.reader
      let output = audio.output
      reader.startReading()
      let queue = DispatchQueue(label: "aquarecover.timeline.audio")
      var finished = false
      audioInput.requestMediaDataWhenReady(on: queue) { [weak self] in
        while audioInput.isReadyForMoreMediaData && !finished {
          if self?.isCancelled ?? true {
            reader.cancelReading()
          }
          if let buffer = output.copyNextSampleBuffer() {
            audioInput.append(buffer)
          } else {
            finished = true
            audioInput.markAsFinished()
            audioDone.leave()
          }
        }
      }
    }

    let sources = clips.map { ClipFrameSource(spec: $0, pipeline: pipeline, canvas: canvas) }
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw pipeline.bridgeError("Could not create sRGB color space.")
    }

    do {
      for frame in 0..<totalFrames {
        if isCancelled { throw AquaMediaPipeline.cancelledError }
        let time = Double(frame) / Double(fps)
        var image = black
        let active = clips.indices.filter { clips[$0].start <= time && time < clips[$0].start + clips[$0].duration }
        if let incomingIndex = active.last {
          var composed = try sources[incomingIndex].frame(atLocal: time - clips[incomingIndex].start)
          let incoming = clips[incomingIndex]
          if active.count > 1, incoming.overlapIn > 0, let outgoingIndex = active.dropLast().last {
            let outgoing = try sources[outgoingIndex].frame(atLocal: time - clips[outgoingIndex].start)
            let amount = min(1, max(0, (time - incoming.start) / incoming.overlapIn))
            composed = dissolve(from: outgoing, to: composed, amount: amount, canvas: canvas)
          }
          image = composed.composited(over: black).cropped(to: canvas)
        }
        // Release sources the playhead has passed.
        for index in clips.indices where clips[index].start + clips[index].duration <= time {
          sources[index].close()
        }

        while !videoInput.isReadyForMoreMediaData {
          if isCancelled { throw AquaMediaPipeline.cancelledError }
          Thread.sleep(forTimeInterval: 0.002)
        }
        guard let pool = adaptor.pixelBufferPool else {
          throw writer.error ?? pipeline.bridgeError("The timeline encoder stopped.")
        }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else {
          throw pipeline.bridgeError("Could not allocate a video frame.")
        }
        pipeline.context.render(image, to: buffer, bounds: canvas, colorSpace: sRGB)
        let presentation = CMTime(value: CMTimeValue(frame), timescale: fps)
        guard adaptor.append(buffer, withPresentationTime: presentation) else {
          throw writer.error ?? pipeline.bridgeError("Could not encode a timeline frame.")
        }
        if frame % 15 == 0 {
          progress(Double(frame) / Double(totalFrames))
        }
      }
    } catch {
      sources.forEach { $0.close() }
      audio?.reader.cancelReading()
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: outputURL)
      throw error
    }
    sources.forEach { $0.close() }
    videoInput.markAsFinished()
    audioDone.wait()

    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else {
      try? FileManager.default.removeItem(at: outputURL)
      throw writer.error ?? pipeline.bridgeError("The timeline movie could not be finished.")
    }
    progress(1)
    return outputURL.path
  }

  private func dissolve(from: CIImage, to: CIImage, amount: Double, canvas: CGRect) -> CIImage {
    guard let filter = CIFilter(name: "CIDissolveTransition") else { return to }
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
    filter.setValue(from.composited(over: black), forKey: kCIInputImageKey)
    filter.setValue(to.composited(over: black), forKey: kCIInputTargetImageKey)
    filter.setValue(amount, forKey: kCIInputTimeKey)
    return filter.outputImage?.cropped(to: canvas) ?? to
  }

  private struct AudioMix {
    let reader: AVAssetReader
    let output: AVAssetReaderAudioMixOutput
  }

  /// Places each unmuted clip's audio at its timeline start on alternating
  /// tracks, so crossfading clips can overlap with opposing volume ramps.
  private func makeAudioMix(clips: [TimelineClipSpec]) throws -> AudioMix? {
    let composition = AVMutableComposition()
    let tracks = (0..<2).compactMap { _ in
      composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    }
    guard tracks.count == 2 else { return nil }
    let parameters = tracks.map { AVMutableAudioMixInputParameters(track: $0) }
    var hasAudio = false
    for (index, clip) in clips.enumerated() where clip.isVideo && !clip.muted {
      let asset = AVURLAsset(url: URL(fileURLWithPath: clip.path))
      guard let source = asset.tracks(withMediaType: .audio).first else { continue }
      let slot = index % 2
      let range = CMTimeRange(
        start: CMTime(seconds: clip.sourceStart, preferredTimescale: 48_000),
        duration: CMTime(seconds: clip.duration, preferredTimescale: 48_000)
      )
      let at = CMTime(seconds: clip.start, preferredTimescale: 48_000)
      do {
        try tracks[slot].insertTimeRange(range, of: source, at: at)
      } catch {
        continue
      }
      hasAudio = true
      if clip.overlapIn > 0 {
        let fade = CMTimeRange(start: at, duration: CMTime(seconds: clip.overlapIn, preferredTimescale: 48_000))
        parameters[slot].setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: fade)
        parameters[1 - slot].setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: fade)
      }
    }
    guard hasAudio else { return nil }
    let mix = AVMutableAudioMix()
    mix.inputParameters = parameters
    let reader = try AVAssetReader(asset: composition)
    let usedTracks = tracks.filter { !$0.segments.isEmpty }
    let output = AVAssetReaderAudioMixOutput(audioTracks: usedTracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 48_000,
      AVNumberOfChannelsKey: 2,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.audioMix = mix
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    return AudioMix(reader: reader, output: output)
  }
}

/// One clip as laid out by the Dart `TimelineLayout`.
private struct TimelineClipSpec {
  init(_ values: [String: Any]) throws {
    guard let path = values["path"] as? String, !path.isEmpty else {
      throw NSError(
        domain: AquaMediaPipeline.errorDomain,
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "A timeline clip has no file."]
      )
    }
    self.path = path
    isVideo = values["kind"] as? String == "video"
    start = timelineDouble(values["start"], fallback: 0)
    duration = max(0.04, timelineDouble(values["duration"], fallback: 3))
    overlapIn = max(0, timelineDouble(values["overlapIn"], fallback: 0))
    sourceStart = max(0, timelineDouble(values["sourceStart"], fallback: 0))
    motion = values["motion"] as? String ?? "none"
    muted = values["muted"] as? Bool ?? false
    settings = values["grade"] as? [String: Any] ?? [:]
    look = values["look"] as? [String: Any] ?? [:]
  }

  let path: String
  let isVideo: Bool
  let start: Double
  let duration: Double
  let overlapIn: Double
  let sourceStart: Double
  let motion: String
  let muted: Bool
  let settings: [String: Any]
  let look: [String: Any]
}

/// Produces graded frames of one clip, in increasing local time.
private final class ClipFrameSource {
  init(spec: TimelineClipSpec, pipeline: AquaMediaPipeline, canvas: CGRect) {
    self.spec = spec
    self.pipeline = pipeline
    self.canvas = canvas
  }

  private let spec: TimelineClipSpec
  private let pipeline: AquaMediaPipeline
  private let canvas: CGRect

  private var prepared = false
  private var closed = false
  private var still: CIImage?
  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var orientation = CGAffineTransform.identity
  private var settings: VideoSettings?
  private var lut: LutSettings?
  private var stats: VideoSceneStats = .fallback
  private var current: (time: Double, image: CIImage)?
  private var pending: (time: Double, image: CIImage)?

  func close() {
    guard !closed else { return }
    closed = true
    reader?.cancelReading()
    reader = nil
    output = nil
    still = nil
    current = nil
    pending = nil
  }

  func frame(atLocal time: Double) throws -> CIImage {
    try prepareIfNeeded()
    if let still = still {
      return place(still, progress: spec.duration > 0 ? time / spec.duration : 0)
    }
    advance(to: time + spec.sourceStart)
    guard let frame = current?.image, let settings = settings, let lut = lut else {
      return CIImage.empty()
    }
    let extent = frame.extent
    let graded = pipeline
      .applyFilters(to: frame, extent: extent, settings: settings, lut: lut, sceneStats: stats)
      .cropped(to: extent)
    return place(graded, progress: 0)
  }

  private func prepareIfNeeded() throws {
    guard !prepared else { return }
    prepared = true
    let settings = VideoSettings(spec.settings)
    let lut = try LutSettings(spec.look)
    self.settings = settings
    self.lut = lut
    let url = URL(fileURLWithPath: spec.path)
    if !spec.isVideo {
      guard var image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        throw pipeline.bridgeError("Could not load \(url.lastPathComponent).")
      }
      image = image.transformed(by: CGAffineTransform(
        translationX: -image.extent.origin.x,
        y: -image.extent.origin.y
      ))
      // Grade a copy no larger than needed for a slow zoom, once.
      let target = max(canvas.width, canvas.height) * (spec.motion == "none" ? 1.0 : 1.3)
      let longSide = max(image.extent.width, image.extent.height)
      if longSide > target {
        let scale = target / longSide
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      }
      let extent = image.extent.integral
      image = image.cropped(to: extent)
      let sceneStats = pipeline.estimateSceneStats(image: image, extent: extent)
      let graded = pipeline
        .applyFilters(to: image, extent: extent, settings: settings, lut: lut, sceneStats: sceneStats)
        .cropped(to: extent)
      guard let cgImage = pipeline.context.createCGImage(graded, from: extent) else {
        throw pipeline.bridgeError("Could not render \(url.lastPathComponent).")
      }
      still = CIImage(cgImage: cgImage)
      return
    }

    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw pipeline.bridgeError("\(url.lastPathComponent) has no video track.")
    }
    let range = CMTimeRange(
      start: CMTime(seconds: spec.sourceStart, preferredTimescale: 600),
      duration: CMTime(seconds: spec.duration + 0.5, preferredTimescale: 600)
    )
    stats = pipeline.estimateSceneStats(asset: asset, timeRange: range)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = range
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw pipeline.bridgeError("Could not read \(url.lastPathComponent).")
    }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? pipeline.bridgeError("Could not read \(url.lastPathComponent).")
    }
    self.reader = reader
    self.output = output
    orientation = track.preferredTransform
  }

  /// Keeps the newest decoded frame at or before [sourceTime].
  private func advance(to sourceTime: Double) {
    while true {
      if pending == nil {
        pending = readFrame()
        if pending == nil { return }
      }
      guard let next = pending else { return }
      if current == nil || next.time <= sourceTime + 0.0001 {
        current = next
        pending = nil
      } else {
        return
      }
    }
  }

  private func readFrame() -> (time: Double, image: CIImage)? {
    guard let output = output,
          let sample = output.copyNextSampleBuffer(),
          let pixels = CMSampleBufferGetImageBuffer(sample) else {
      return nil
    }
    let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
    var image = CIImage(cvPixelBuffer: pixels).transformed(by: orientation)
    image = image.transformed(by: CGAffineTransform(
      translationX: -image.extent.origin.x,
      y: -image.extent.origin.y
    ))
    return (time, image)
  }

  /// Fits [image] into the canvas: letterboxed, or filling it with a slow
  /// zoom for photos that have motion.
  private func place(_ image: CIImage, progress: Double) -> CIImage {
    let extent = image.extent
    guard extent.width > 0, extent.height > 0 else { return image }
    let fit = min(canvas.width / extent.width, canvas.height / extent.height)
    let cover = max(canvas.width / extent.width, canvas.height / extent.height)
    var scale = fit
    if !spec.isVideo, spec.motion != "none" {
      let t = min(1, max(0, progress))
      let zoom = spec.motion == "zoomIn" ? 1 + 0.15 * t : 1.15 - 0.15 * t
      scale = cover * zoom
    }
    let width = extent.width * scale
    let height = extent.height * scale
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .concatenating(CGAffineTransform(
        translationX: (canvas.width - width) / 2,
        y: (canvas.height - height) / 2
      ))
    return image.transformed(by: transform).cropped(to: canvas)
  }
}

private func timelineDouble(_ value: Any?, fallback: Double) -> Double {
  if let number = value as? NSNumber {
    let double = number.doubleValue
    return double.isFinite ? double : fallback
  }
  return fallback
}

private func timelineInt(_ value: Any?, fallback: Int) -> Int {
  (value as? NSNumber)?.intValue ?? fallback
}
