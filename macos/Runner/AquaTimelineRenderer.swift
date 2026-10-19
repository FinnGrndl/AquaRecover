import AVFoundation
import CoreImage
import Foundation

/// Renders an AquaRecover timeline into one H.264 movie by executing the
/// render plan the Dart `TimelineCompiler` resolved (contract v2, built by
/// `TimelineRenderService.planArguments`). Shared by the iOS and macOS
/// runners; the Flutter glue lives in IosVideoProcessor.swift and
/// MacMediaProcessor.swift.
///
/// Every output frame is pulled through Core Image, bottom to top:
/// 1. the main clips active at that time (the outgoing and the incoming clip
///    while they dissolve), each decoded at `sourceStart + local × speed`,
///    given the full AquaMediaPipeline grade and look, then its filters,
///    fitted into the canvas, and moved by its transform keys;
/// 2. the layers in plan order: overlay videos and photos, the generated
///    title and effect PNGs, and solid colours (fades, dips, strobe flashes),
///    each stretched into its keyed rect, rotated about the rect centre, and
///    composited source-over with its opacity.
/// Audio segments go on one composition track per lane, are time scaled with
/// their pitch preserved, mixed with AVAudioMix volume ramps, and written
/// alongside. Native code never re-derives layout, animation, or effect maths.
///
/// Plan geometry has a top-left origin, y pointing down, and clockwise
/// rotation; Core Image is y-up and counter-clockwise, so y values and angles
/// are flipped wherever a plan value meets Core Image. Blending happens on
/// gamma-encoded values (the pipeline's CIContext has no working colour
/// space), like the Android and ffmpeg renderers.
final class AquaTimelineRenderer {
  init(pipeline: AquaMediaPipeline) {
    self.pipeline = pipeline
  }

  /// Version of the `renderTimeline` arguments this renderer executes.
  static let contractVersion = 2

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

    let plan = try TimelinePlanSpec(args)
    let width = plan.width
    let height = plan.height
    guard (16...8192).contains(width), (16...8192).contains(height), (12...60).contains(plan.frameRate) else {
      throw pipeline.bridgeError("The timeline output size is out of range.")
    }
    let fps = Int32(plan.frameRate)
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    // Frames strictly inside the movie; the tolerance keeps 11.4 s at 30 fps
    // at 342 frames despite floating point.
    let totalFrames = Int((plan.duration * Double(fps) - 1e-6).rounded(.up))
    guard totalFrames > 0 else { throw pipeline.bridgeError("The timeline is empty.") }
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw pipeline.bridgeError("Could not create sRGB color space.")
    }

    let outputURL = URL(fileURLWithPath: plan.outputPath)
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

    let audio = try makeAudioMix(segments: plan.audio, duration: plan.duration)
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

    let compositor = TimelineCompositor(
      clips: plan.clips,
      layers: plan.layers,
      pipeline: pipeline,
      canvas: canvas
    )
    do {
      for frame in 0..<totalFrames {
        if isCancelled { throw AquaMediaPipeline.cancelledError }
        let time = Double(frame) / Double(fps)
        // One pool per frame, so its Core Image graph and decoded buffers are
        // released before the next frame starts.
        try autoreleasepool {
          let image = try compositor.frame(at: time, frameIndex: frame)
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
          // Release the readers and images of items the playhead has passed.
          compositor.release(through: time)
        }
        if frame % 15 == 0 {
          progress(Double(frame) / Double(totalFrames))
        }
      }
    } catch {
      compositor.close()
      audio?.reader.cancelReading()
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: outputURL)
      throw error
    }
    compositor.close()
    videoInput.markAsFinished()
    // Wait for the audio pump, unless the writer failed or the render was
    // cancelled underneath it (the pump might never be asked for data again).
    while audioDone.wait(timeout: .now() + 0.25) == .timedOut {
      guard writer.status == .failed || isCancelled else { continue }
      audio?.reader.cancelReading()
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: outputURL)
      if isCancelled { throw AquaMediaPipeline.cancelledError }
      throw writer.error ?? pipeline.bridgeError("The timeline audio could not be written.")
    }

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

  private struct AudioMix {
    let reader: AVAssetReader
    let output: AVAssetReaderAudioMixOutput
  }

  /// Lays every audio segment out on one composition track per plan lane
  /// (segments on a lane never overlap). Each is inserted at its timeline
  /// start and time scaled by its speed straight away, so later segments on
  /// the lane keep their places; its volume and fades become AVAudioMix
  /// ramps, and the spectral time-pitch algorithm keeps scaled audio at its
  /// pitch. Returns `nil` when no segment has sound (a video without an audio
  /// track is skipped).
  private func makeAudioMix(segments: [TimelineAudioSpec], duration: Double) throws -> AudioMix? {
    let ordered = segments.sorted { ($0.lane, $0.start) < ($1.lane, $1.start) }
    guard !ordered.isEmpty else { return nil }
    let composition = AVMutableComposition()
    var tracks: [Int: AVMutableCompositionTrack] = [:]
    var parameters: [Int: AVMutableAudioMixInputParameters] = [:]
    var sources: [String: AVAssetTrack] = [:]
    var silent: Set<String> = []
    for (index, segment) in ordered.enumerated() {
      if sources[segment.path] == nil, !silent.contains(segment.path) {
        let asset = AVURLAsset(
          url: URL(fileURLWithPath: segment.path),
          options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        if let track = asset.tracks(withMediaType: .audio).first {
          sources[segment.path] = track
        } else {
          silent.insert(segment.path)
        }
      }
      guard let source = sources[segment.path] else { continue }

      // The source seconds that exist and land inside the movie.
      var from = max(segment.sourceStart, segment.sourceStart - segment.start * segment.speed)
      var to = min(
        segment.sourceStart + segment.sourceDuration,
        segment.sourceStart + (duration - segment.start) * segment.speed
      )
      let available = source.timeRange
      if available.start.isNumeric, available.duration.isNumeric {
        from = max(from, available.start.seconds)
        to = min(to, available.end.seconds)
      }
      guard to - from > 0.001 else { continue }

      let track: AVMutableCompositionTrack
      if let existing = tracks[segment.lane] {
        track = existing
      } else {
        guard let created = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { continue }
        tracks[segment.lane] = created
        track = created
      }
      // Never insert inside the previous segment (that would split it), even
      // when time rounding puts the two a tick apart.
      let laneEnd = track.segments.last?.timeMapping.target.end ?? .zero
      var at = timelineTime(segment.start + (from - segment.sourceStart) / segment.speed)
      if CMTimeCompare(at, laneEnd) < 0 {
        at = laneEnd
      }
      let sourceRange = CMTimeRange(start: timelineTime(from), end: timelineTime(to))
      do {
        try track.insertTimeRange(sourceRange, of: source, at: at)
      } catch {
        continue
      }
      let target = timelineTime((to - from) / segment.speed)
      if abs(segment.speed - 1) > 0.0001 {
        track.scaleTimeRange(CMTimeRange(start: at, duration: sourceRange.duration), toDuration: target)
      }

      let laneParameters: AVMutableAudioMixInputParameters
      if let existing = parameters[segment.lane] {
        laneParameters = existing
      } else {
        laneParameters = AVMutableAudioMixInputParameters(track: track)
        laneParameters.audioTimePitchAlgorithm = .spectral
        parameters[segment.lane] = laneParameters
      }
      let playFrom = at.seconds
      let playTo = playFrom + target.seconds
      let next = index + 1 < ordered.count ? ordered[index + 1] : nil
      var silenceAfter = false
      if let next = next, next.lane == segment.lane, next.start > playTo + 0.001 {
        silenceAfter = true
      }
      applyVolume(
        of: segment,
        from: playFrom,
        to: playTo,
        silenceAfter: silenceAfter,
        parameters: laneParameters
      )
    }

    var usedTracks: [AVMutableCompositionTrack] = []
    var usedParameters: [AVAudioMixInputParameters] = []
    for lane in tracks.keys.sorted() {
      guard let track = tracks[lane], !track.segments.isEmpty else { continue }
      usedTracks.append(track)
      if let laneParameters = parameters[lane] {
        usedParameters.append(laneParameters)
      }
    }
    guard !usedTracks.isEmpty else { return nil }
    let mix = AVMutableAudioMix()
    mix.inputParameters = usedParameters
    let reader = try AVAssetReader(asset: composition)
    reader.timeRange = CMTimeRange(start: .zero, duration: timelineTime(duration))
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
    output.audioTimePitchAlgorithm = .spectral
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    return AudioMix(reader: reader, output: output)
  }

  /// Gives [segment] its volume on its lane between the timeline times [from]
  /// and [to] where it actually plays: linear fade ramps (their product,
  /// sampled, where the two overlap), then silence when the lane rests until
  /// its next segment.
  private func applyVolume(
    of segment: TimelineAudioSpec,
    from: Double,
    to: Double,
    silenceAfter: Bool,
    parameters: AVMutableAudioMixInputParameters
  ) {
    var times = [from, to]
    for edge in [segment.start + segment.fadeIn, segment.end - segment.fadeOut] where edge > from && edge < to {
      times.append(edge)
    }
    let overlapFrom = max(from, segment.end - segment.fadeOut)
    let overlapTo = min(to, segment.start + segment.fadeIn)
    if segment.fadeIn > 0, segment.fadeOut > 0, overlapTo - overlapFrom > 0.001 {
      for step in 1..<8 {
        times.append(overlapFrom + (overlapTo - overlapFrom) * Double(step) / 8)
      }
    }
    times.sort()
    var points: [Double] = []
    for time in times {
      if let last = points.last, time - last < 0.0005 { continue }
      points.append(time)
    }
    let gains = points.map { Float(segment.gain(at: $0)) }
    // A ramp sets the volume from its own start, so only a level start needs
    // an explicit volume; after a ramp, its end volume holds.
    if gains.count < 2 || abs(gains[1] - gains[0]) < 0.0001 {
      parameters.setVolume(gains[0], at: timelineTime(points[0]))
    }
    for index in points.indices.dropFirst() where abs(gains[index] - gains[index - 1]) >= 0.0001 {
      parameters.setVolumeRamp(
        fromStartVolume: gains[index - 1],
        toEndVolume: gains[index],
        timeRange: CMTimeRange(start: timelineTime(points[index - 1]), end: timelineTime(points[index]))
      )
    }
    if silenceAfter {
      parameters.setVolume(0, at: timelineTime(to))
    }
  }
}

// MARK: - Frame composition

/// Draws the plan at one output time: the main clips over black, then every
/// active layer, bottom to top. Owns the readers and image caches of all
/// items and releases them once the playhead has passed an item.
private final class TimelineCompositor {
  init(clips: [TimelineClipSpec], layers: [TimelineLayerSpec], pipeline: AquaMediaPipeline, canvas: CGRect) {
    self.clips = clips
    self.layers = layers
    self.canvas = canvas
    clipSources = clips.enumerated().map { index, clip in
      ClipFrameSource(spec: clip, salt: index, pipeline: pipeline, canvas: canvas)
    }
    layerSources = layers.enumerated().map { index, layer in
      LayerFrameSource(spec: layer, salt: clips.count + index, pipeline: pipeline, canvas: canvas)
    }
    black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
  }

  private let clips: [TimelineClipSpec]
  private let layers: [TimelineLayerSpec]
  private let canvas: CGRect
  private let clipSources: [ClipFrameSource]
  private let layerSources: [LayerFrameSource]
  private let black: CIImage

  /// The finished canvas at timeline [time]; [frameIndex] seeds the grain.
  func frame(at time: Double, frameIndex: Int) throws -> CIImage {
    var image = black
    let active = clips.indices.filter { clips[$0].start <= time && time < clips[$0].end }
    if let incomingIndex = active.last {
      let incoming = clips[incomingIndex]
      var composed = try clipSources[incomingIndex].frame(
        atLocal: time - incoming.start,
        frameIndex: frameIndex
      )
      if active.count > 1, incoming.overlapIn > 0, let outgoingIndex = active.dropLast().last {
        let outgoing = try clipSources[outgoingIndex].frame(
          atLocal: time - clips[outgoingIndex].start,
          frameIndex: frameIndex
        )
        let amount = min(1, max(0, (time - incoming.start) / incoming.overlapIn))
        composed = dissolve(from: outgoing, to: composed, amount: amount)
      }
      image = composed.composited(over: black)
    }
    for index in layers.indices where layers[index].start <= time && time < layers[index].end {
      if let layer = try layerSources[index].frame(atLocal: time - layers[index].start, frameIndex: frameIndex) {
        image = layer.composited(over: image)
      }
    }
    return image.cropped(to: canvas)
  }

  /// Closes the readers and caches of items that ended at or before [time].
  func release(through time: Double) {
    for index in clips.indices where clips[index].end <= time {
      clipSources[index].close()
    }
    for index in layers.indices where layers[index].end <= time {
      layerSources[index].close()
    }
  }

  func close() {
    clipSources.forEach { $0.close() }
    layerSources.forEach { $0.close() }
  }

  private func dissolve(from: CIImage, to: CIImage, amount: Double) -> CIImage {
    guard let filter = CIFilter(name: "CIDissolveTransition") else { return to }
    filter.setValue(from.composited(over: black), forKey: kCIInputImageKey)
    filter.setValue(to.composited(over: black), forKey: kCIInputTargetImageKey)
    filter.setValue(amount, forKey: kCIInputTimeKey)
    return filter.outputImage?.cropped(to: canvas) ?? to
  }
}

/// Produces the frames of one main clip at increasing local times: decoded at
/// `sourceStart + local × speed`, graded (+ look), filtered, fitted into the
/// canvas, moved by the clip's keys, and cropped to the canvas (transparent
/// where the frame does not reach, so the caller's black shows).
private final class ClipFrameSource {
  init(spec: TimelineClipSpec, salt: Int, pipeline: AquaMediaPipeline, canvas: CGRect) {
    self.spec = spec
    self.salt = salt
    self.pipeline = pipeline
    self.canvas = canvas
  }

  private let spec: TimelineClipSpec
  private let salt: Int
  private let pipeline: AquaMediaPipeline
  private let canvas: CGRect

  private var prepared = false
  private var closed = false
  private var still: CIImage?
  private var video: VideoFrameReader?
  private var settings: VideoSettings?
  private var lut: LutSettings?
  private var stats: VideoSceneStats = .fallback

  func close() {
    guard !closed else { return }
    closed = true
    video?.close()
    video = nil
    still = nil
  }

  func frame(atLocal time: Double, frameIndex: Int) throws -> CIImage {
    guard !closed else { return CIImage.empty() }
    try prepareIfNeeded()
    let source: CIImage
    if let still = still {
      source = still
    } else {
      guard let video = video, let settings = settings, let lut = lut,
            let frame = try video.frame(at: spec.sourceStart + time * spec.speed) else {
        return CIImage.empty()
      }
      let extent = frame.extent
      let graded = pipeline
        .applyFilters(to: frame, extent: extent, settings: settings, lut: lut, sceneStats: stats)
        .cropped(to: extent)
      source = TimelineFilterOps.colorMatrix(graded, spec.filters.colorMatrix)
    }
    return place(source, atLocal: time, frameIndex: frameIndex)
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
      var image = try timelineLoadImage(url, pipeline: pipeline)
      // Grade, once, a copy no larger than the canvas shows at the largest
      // key scale; the colour matrix is static, so it is baked in too.
      let maxScale = max(1, spec.keys.map(\.scale).max() ?? 1)
      image = timelineResized(image, scale: fitScale(for: image.extent) * maxScale, highQuality: true)
      let extent = image.extent
      let sceneStats = pipeline.estimateSceneStats(image: image, extent: extent)
      let graded = pipeline
        .applyFilters(to: image, extent: extent, settings: settings, lut: lut, sceneStats: sceneStats)
        .cropped(to: extent)
      let colored = TimelineFilterOps.colorMatrix(graded, spec.filters.colorMatrix)
      guard let cgImage = pipeline.context.createCGImage(colored, from: extent) else {
        throw pipeline.bridgeError("Could not render \(url.lastPathComponent).")
      }
      still = CIImage(cgImage: cgImage)
      return
    }
    let reader = try VideoFrameReader(
      url: url,
      sourceStart: spec.sourceStart,
      sourceDuration: spec.sourceDuration,
      pipeline: pipeline
    )
    stats = pipeline.estimateSceneStats(asset: reader.asset, timeRange: reader.timeRange)
    video = reader
  }

  /// Scale that fits a frame of [extent] into the canvas: the whole frame
  /// (letterboxed) for `contain`, the canvas filled for `cover`.
  private func fitScale(for extent: CGRect) -> Double {
    guard extent.width > 0, extent.height > 0 else { return 1 }
    let x = Double(canvas.width / extent.width)
    let y = Double(canvas.height / extent.height)
    return spec.cover ? max(x, y) : min(x, y)
  }

  /// Fits [image] into the canvas, centred, then applies the key at [time]:
  /// with `C` the canvas centre, a point `p` goes to
  /// `C + (x, y) + R(rotation) · scale · (p − C)`.
  private func place(_ image: CIImage, atLocal time: Double, frameIndex: Int) -> CIImage {
    let extent = image.extent
    guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return image }
    let fit = CGFloat(fitScale(for: extent))
    let key = evaluateKeys(spec.keys, at: time) ?? TimelineTransformKey.identity
    let fitted = CGAffineTransform(scaleX: fit, y: fit)
    // About the canvas centre: scale, rotate clockwise on screen (a negative
    // angle in Core Image's y-up space), then move by (x, y) with y down.
    let motion = CGAffineTransform(translationX: -extent.midX * fit, y: -extent.midY * fit)
      .concatenating(CGAffineTransform(scaleX: CGFloat(key.scale), y: CGFloat(key.scale)))
      .concatenating(CGAffineTransform(rotationAngle: CGFloat(-key.rotation * Double.pi / 180)))
      .concatenating(CGAffineTransform(
        translationX: canvas.midX + CGFloat(key.x),
        y: canvas.midY - CGFloat(key.y)
      ))
    var placed: CIImage
    if spec.filters.hasSpatial {
      // Blur and sharpen sigmas are output pixels after fitting.
      placed = TimelineFilterOps
        .spatial(image.transformed(by: fitted), filters: spec.filters)
        .transformed(by: motion)
    } else {
      placed = image.transformed(by: fitted.concatenating(motion))
    }
    placed = placed.cropped(to: canvas)
    // Grain last, in output pixels; alpha keeps it off the letterbox.
    return TimelineFilterOps.grain(placed, amount: spec.filters.grain, frameIndex: frameIndex, salt: salt)
  }
}

/// Produces one layer at increasing local times: its source stretched into
/// the keyed rect, filtered, rotated about the rect centre, cropped to the
/// canvas, and faded by the key's opacity.
private final class LayerFrameSource {
  init(spec: TimelineLayerSpec, salt: Int, pipeline: AquaMediaPipeline, canvas: CGRect) {
    self.spec = spec
    self.salt = salt
    self.pipeline = pipeline
    self.canvas = canvas
  }

  private let spec: TimelineLayerSpec
  private let salt: Int
  private let pipeline: AquaMediaPipeline
  private let canvas: CGRect

  private var prepared = false
  private var closed = false
  private var still: CIImage?
  private var video: VideoFrameReader?
  /// `nil` for layers drawn with their own colours.
  private var settings: VideoSettings?
  private var lut: LutSettings?
  private var stats: VideoSceneStats = .fallback

  func close() {
    guard !closed else { return }
    closed = true
    video?.close()
    video = nil
    still = nil
  }

  /// The layer on a transparent canvas at [time] seconds into it, or `nil`
  /// when none of it is visible.
  func frame(atLocal time: Double, frameIndex: Int) throws -> CIImage? {
    guard !closed, let key = evaluateKeys(spec.keys, at: time) else { return nil }
    let opacity = min(1, max(0, key.opacity)) * spec.colorAlpha
    guard opacity > 0.001, key.w >= 0.5, key.h >= 0.5 else { return nil }
    let width = CGFloat(key.w)
    let height = CGFloat(key.h)
    // The unrotated rect is (x, y, w, h) from the top-left, y down; Core
    // Image puts its centre at (x + w/2, H − y − h/2) and turns it clockwise
    // with a negative angle.
    let placement = CGAffineTransform(translationX: -width / 2, y: -height / 2)
      .concatenating(CGAffineTransform(rotationAngle: CGFloat(-key.rotation * Double.pi / 180)))
      .concatenating(CGAffineTransform(
        translationX: CGFloat(key.x) + width / 2,
        y: canvas.height - CGFloat(key.y) - height / 2
      ))
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    guard rect.applying(placement).intersects(canvas) else { return nil }
    try prepareIfNeeded()

    var image: CIImage
    if spec.kind == .color {
      image = CIImage(color: spec.color).cropped(to: rect).transformed(by: placement)
    } else {
      guard let source = try content(atLocal: time) else { return nil }
      let extent = source.extent
      guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return nil }
      // Stretched into the rect (the compiler matched its aspect to the source).
      let stretch = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        .concatenating(CGAffineTransform(scaleX: width / extent.width, y: height / extent.height))
      if abs(key.rotation) < 0.0001, abs(width - extent.width) < 1, abs(height - extent.height) < 1 {
        // Unrotated and within a pixel of its rect (titles, full-canvas
        // textures): drawn 1:1 at whole pixels about the rect centre, so the
        // source is not resampled.
        let filtered = spec.filters.hasSpatial ? TimelineFilterOps.spatial(source, filters: spec.filters) : source
        image = filtered.transformed(by: CGAffineTransform(
          translationX: (CGFloat(key.x) + (width - extent.width) / 2).rounded() - extent.minX,
          y: (canvas.height - CGFloat(key.y) - (height + extent.height) / 2).rounded() - extent.minY
        ))
      } else if spec.filters.hasSpatial {
        // Blur and sharpen sigmas are output pixels of the rect.
        image = TimelineFilterOps
          .spatial(source.transformed(by: stretch), filters: spec.filters)
          .transformed(by: placement)
      } else {
        image = source.transformed(by: stretch.concatenating(placement))
      }
    }
    image = image.cropped(to: canvas)
    image = TimelineFilterOps.grain(image, amount: spec.filters.grain, frameIndex: frameIndex, salt: salt)
    return TimelineFilterOps.opacity(image, opacity)
  }

  /// The source pixels at [time] with the grade, look, and colour matrix
  /// applied; `nil` before a video's first frame.
  private func content(atLocal time: Double) throws -> CIImage? {
    if let still = still { return still }
    guard let video = video,
          let frame = try video.frame(at: spec.sourceStart + time * spec.speed) else {
      return nil
    }
    var image = frame
    if let settings = settings, let lut = lut {
      // Grade no more pixels than the layer ever shows.
      image = timelineResized(image, scale: baseScale(for: image.extent), highQuality: false)
      let extent = image.extent
      image = pipeline
        .applyFilters(to: image, extent: extent, settings: settings, lut: lut, sceneStats: stats)
        .cropped(to: extent)
    }
    return TimelineFilterOps.colorMatrix(image, spec.filters.colorMatrix)
  }

  /// Downscale that keeps a source of [extent] at least as large as the
  /// largest rect of the layer's keys (never enlarging).
  private func baseScale(for extent: CGRect) -> Double {
    guard extent.width > 0, extent.height > 0 else { return 1 }
    return min(1, max(spec.maxWidth / Double(extent.width), spec.maxHeight / Double(extent.height)))
  }

  private func prepareIfNeeded() throws {
    guard !prepared else { return }
    prepared = true
    if spec.grade != nil || spec.look != nil {
      settings = VideoSettings(spec.grade ?? timelineIdentityGrade)
      lut = try LutSettings(spec.look ?? [:])
    }
    guard let path = spec.path else { return }
    let url = URL(fileURLWithPath: path)
    switch spec.kind {
    case .color:
      return
    case .image:
      // Decoded, downscaled, graded, and coloured once. Grades assume opaque
      // pixels, as photo overlays are.
      var image = try timelineLoadImage(url, pipeline: pipeline)
      image = timelineResized(image, scale: baseScale(for: image.extent), highQuality: true)
      let extent = image.extent
      if let settings = settings, let lut = lut {
        let sceneStats = pipeline.estimateSceneStats(image: image, extent: extent)
        image = pipeline
          .applyFilters(to: image, extent: extent, settings: settings, lut: lut, sceneStats: sceneStats)
          .cropped(to: extent)
      }
      image = TimelineFilterOps.colorMatrix(image, spec.filters.colorMatrix)
      guard let cgImage = pipeline.context.createCGImage(image, from: extent) else {
        throw pipeline.bridgeError("Could not render \(url.lastPathComponent).")
      }
      still = CIImage(cgImage: cgImage)
    case .video:
      let reader = try VideoFrameReader(
        url: url,
        sourceStart: spec.sourceStart,
        sourceDuration: spec.sourceDuration,
        pipeline: pipeline
      )
      if settings != nil {
        stats = pipeline.estimateSceneStats(asset: reader.asset, timeRange: reader.timeRange)
      }
      video = reader
    }
  }
}

/// Decodes one video track forward only from `sourceStart`, keeping the
/// newest frame at or before the requested source time. Frames come upright
/// with their origin at zero.
private final class VideoFrameReader {
  init(url: URL, sourceStart: Double, sourceDuration: Double, pipeline: AquaMediaPipeline) throws {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw pipeline.bridgeError("\(url.lastPathComponent) has no video track.")
    }
    let range = CMTimeRange(
      start: CMTime(seconds: max(0, sourceStart), preferredTimescale: 600),
      duration: CMTime(seconds: max(0, sourceDuration) + 0.5, preferredTimescale: 600)
    )
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
    self.asset = asset
    self.pipeline = pipeline
    name = url.lastPathComponent
    timeRange = range
    self.reader = reader
    self.output = output
    // preferredTransform maps y-down pixels; conjugated with a vertical flip
    // it turns the frame the same way in Core Image's y-up space (the origin
    // is reset per frame).
    let flip = CGAffineTransform(scaleX: 1, y: -1)
    orientation = flip.concatenating(track.preferredTransform).concatenating(flip)
  }

  let asset: AVAsset
  /// Source seconds the reader decodes, with 0.5 s of slack at the end.
  let timeRange: CMTimeRange
  private let pipeline: AquaMediaPipeline
  private let name: String
  private let orientation: CGAffineTransform
  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var current: (time: Double, image: CIImage)?
  private var pending: (time: Double, image: CIImage)?

  func close() {
    reader?.cancelReading()
    reader = nil
    output = nil
    current = nil
    pending = nil
  }

  /// The newest frame at or before [sourceTime]: the first frame until the
  /// stream reaches it, the last one after the stream ends.
  func frame(at sourceTime: Double) throws -> CIImage? {
    while true {
      if pending == nil {
        pending = try readFrame()
        if pending == nil { break }
      }
      guard let next = pending else { break }
      if current == nil || next.time <= sourceTime + 0.0001 {
        current = next
        pending = nil
      } else {
        break
      }
    }
    return current?.image
  }

  private func readFrame() throws -> (time: Double, image: CIImage)? {
    guard let reader = reader, let output = output, reader.status == .reading else { return nil }
    while let sample = output.copyNextSampleBuffer() {
      guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
      let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
      var image = CIImage(cvPixelBuffer: pixels).transformed(by: orientation)
      image = image.transformed(by: CGAffineTransform(
        translationX: -image.extent.origin.x,
        y: -image.extent.origin.y
      ))
      return (time, image)
    }
    if reader.status == .failed {
      throw reader.error ?? pipeline.bridgeError("Could not decode \(name).")
    }
    return nil
  }
}

// MARK: - Filters

/// The per-pixel filters of the plan (`PlanFilters`) in the order the
/// contract fixes: colour matrix, Gaussian blur, unsharp mask, then grain;
/// plus the layer opacity. Kernels see premultiplied pixels.
private enum TimelineFilterOps {
  /// Multiplies all four premultiplied channels, i.e. the opacity.
  private static let opacityKernel = CIColorKernel(source: """
    kernel vec4 aquaTimelineOpacity(__sample s, float opacity) {
      return s * opacity;
    }
  """)

  /// The plan's 4×5 matrix on straight colour (offsets in 0…1), clamped.
  private static let colorMatrixKernel = CIColorKernel(source: """
    kernel vec4 aquaTimelineColorMatrix(
      __sample s,
      vec4 rowR,
      vec4 rowG,
      vec4 rowB,
      vec4 rowA,
      vec4 offsets
    ) {
      vec4 c = unpremultiply(s);
      vec4 m = vec4(dot(c, rowR), dot(c, rowG), dot(c, rowB), dot(c, rowA)) + offsets;
      return premultiply(clamp(m, vec4(0.0), vec4(1.0)));
    }
  """)

  /// `out = in + amount · (in − blurred)`.
  private static let unsharpKernel = CIColorKernel(source: """
    kernel vec4 aquaTimelineUnsharp(__sample s, __sample blurred, float amount) {
      vec3 rgb = s.rgb + amount * (s.rgb - blurred.rgb);
      return vec4(clamp(rgb, vec3(0.0), vec3(s.a)), s.a);
    }
  """)

  /// Adds zero-mean monochrome noise from a uniform 0…1 sample.
  private static let grainKernel = CIColorKernel(source: """
    kernel vec4 aquaTimelineGrain(__sample s, __sample random, float amount) {
      float g = (random.r - 0.5) * amount * s.a;
      return vec4(clamp(s.rgb + vec3(g), vec3(0.0), vec3(s.a)), s.a);
    }
  """)

  /// Four independent uniform 0…1 values per pixel, infinite extent.
  private static let noise = CIFilter(name: "CIRandomGenerator")?.outputImage

  static func colorMatrix(_ image: CIImage, _ matrix: [Double]?) -> CIImage {
    guard let m = matrix, m.count == 20 else { return image }
    let extent = image.extent
    func row(_ start: Int) -> CIVector {
      CIVector(x: CGFloat(m[start]), y: CGFloat(m[start + 1]), z: CGFloat(m[start + 2]), w: CGFloat(m[start + 3]))
    }
    let offsets = CIVector(x: CGFloat(m[4]), y: CGFloat(m[9]), z: CGFloat(m[14]), w: CGFloat(m[19]))
    if let kernel = colorMatrixKernel,
       let output = kernel.apply(extent: extent, arguments: [image, row(0), row(5), row(10), row(15), offsets]) {
      return output
    }
    return image
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": row(0),
        "inputGVector": row(5),
        "inputBVector": row(10),
        "inputAVector": row(15),
        "inputBiasVector": offsets,
      ])
      .applyingFilter("CIColorClamp", parameters: [:])
      .cropped(to: extent)
  }

  /// Gaussian blur, then unsharp mask; sigmas in pixels of [image].
  static func spatial(_ image: CIImage, filters: TimelineFilters) -> CIImage {
    let extent = image.extent
    var output = image
    if filters.blurSigma > TimelineFilters.minSigma {
      output = output.clampedToExtent().applyingGaussianBlur(sigma: filters.blurSigma).cropped(to: extent)
    }
    if filters.sharpens {
      let blurred = output.clampedToExtent()
        .applyingGaussianBlur(sigma: filters.sharpenSigma)
        .cropped(to: extent)
      if let kernel = unsharpKernel,
         let sharpened = kernel.apply(extent: extent, arguments: [output, blurred, filters.sharpen]) {
        output = sharpened
      } else {
        output = output
          .applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: filters.sharpenSigma,
            kCIInputIntensityKey: filters.sharpen,
          ])
          .cropped(to: extent)
      }
    }
    return output
  }

  /// Adds monochrome noise with standard deviation [amount] (0…1 units),
  /// weighted by alpha, with a new pattern for every frame and item.
  static func grain(_ image: CIImage, amount: Double, frameIndex: Int, salt: Int) -> CIImage {
    guard amount > 0.0001, let kernel = grainKernel, let noise = noise else { return image }
    let shifted = noise.transformed(by: timelineNoiseOffset(frame: frameIndex, salt: salt))
    // Uniform 0…1 noise has a standard deviation of 1/√12.
    let scale = amount * 12.0.squareRoot()
    return kernel.apply(extent: image.extent, arguments: [image, shifted, scale]) ?? image
  }

  static func opacity(_ image: CIImage, _ opacity: Double) -> CIImage {
    guard opacity < 0.999 else { return image }
    if let kernel = opacityKernel,
       let output = kernel.apply(extent: image.extent, arguments: [image, opacity]) {
      return output
    }
    return image.applyingFilter("CIColorMatrix", parameters: [
      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
    ])
  }
}

/// Whole-pixel offset into the infinite random image for one frame of one
/// item (SplitMix64), so every frame gets new grain and renders repeat.
private func timelineNoiseOffset(frame: Int, salt: Int) -> CGAffineTransform {
  var z = UInt64(truncatingIfNeeded: frame) &* 0x9E37_79B9_7F4A_7C15
    &+ UInt64(truncatingIfNeeded: salt) &* 0xD1B5_4A32_D192_ED03
  z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
  z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
  z ^= z >> 31
  return CGAffineTransform(translationX: CGFloat(z & 0xFFF), y: CGFloat((z >> 12) & 0xFFF))
}

/// The image at [url], upright, with its origin at zero.
private func timelineLoadImage(_ url: URL, pipeline: AquaMediaPipeline) throws -> CIImage {
  guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
        !image.extent.isEmpty, !image.extent.isInfinite else {
    throw pipeline.bridgeError("Could not load \(url.lastPathComponent).")
  }
  return image.transformed(by: CGAffineTransform(
    translationX: -image.extent.origin.x,
    y: -image.extent.origin.y
  ))
}

/// [image] scaled by [scale] to whole pixels with its origin at zero, never
/// enlarged. [highQuality] uses Lanczos, for images prepared once.
private func timelineResized(_ image: CIImage, scale: Double, highQuality: Bool) -> CIImage {
  let extent = image.extent
  guard scale < 0.999, extent.width >= 1, extent.height >= 1, !extent.isInfinite else { return image }
  let width = max(1, (Double(extent.width) * scale).rounded())
  let height = max(1, (Double(extent.height) * scale).rounded())
  let scaleX = width / Double(extent.width)
  let scaleY = height / Double(extent.height)
  let target = CGRect(x: 0, y: 0, width: width, height: height)
  let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
  if highQuality, let filter = CIFilter(name: "CILanczosScaleTransform") {
    filter.setValue(normalized, forKey: kCIInputImageKey)
    filter.setValue(scaleY, forKey: kCIInputScaleKey)
    filter.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
    if let output = filter.outputImage {
      return output.cropped(to: target)
    }
  }
  return normalized
    .transformed(by: CGAffineTransform(scaleX: CGFloat(scaleX), y: CGFloat(scaleY)))
    .cropped(to: target)
}

/// A grade that changes nothing, for layers with a look but no grade
/// (`VideoSettings` defaults are the Auto restoration, not identity).
private let timelineIdentityGrade: [String: Any] = [
  "recovery": 0.0,
  "redRecovery": 0.0,
  "autoWhiteBalance": 0.0,
  "contrastStretch": 0.0,
  "contrast": 1.0,
  "gamma": 1.0,
  "saturation": 1.0,
  "vibrance": 0.0,
  "clarity": 0.0,
  "sharpness": 0.0,
  "hazeReduction": 0.0,
  "highlightProtection": 0.0,
  "hue": 0.0,
  "brightness": 0.0,
  "exposure": 0.0,
  "highlights": 0.0,
  "shadows": 0.0,
  "blackPoint": 0.0,
  "vignette": 0.0,
  "temperature": 0.0,
  "tint": 0.0,
]

// MARK: - Plan

/// The `renderTimeline` arguments: a compiled `TimelineRenderPlan`.
private struct TimelinePlanSpec {
  init(_ args: [String: Any]) throws {
    let version = timelineInt(args["version"], fallback: 0)
    guard version == AquaTimelineRenderer.contractVersion else {
      throw timelineError("Timeline format \(version) is not supported by this renderer.")
    }
    guard let outputPath = args["outputPath"] as? String, !outputPath.isEmpty,
          let rawClips = args["clips"] as? [[String: Any]], !rawClips.isEmpty else {
      throw timelineError("outputPath and at least one clip are required.")
    }
    self.outputPath = outputPath
    width = timelineInt(args["width"], fallback: 1920)
    height = timelineInt(args["height"], fallback: 1080)
    frameRate = timelineInt(args["frameRate"], fallback: 30)
    clips = try rawClips.map { try TimelineClipSpec($0) }
    layers = try (args["layers"] as? [[String: Any]] ?? []).map { try TimelineLayerSpec($0) }
    audio = (args["audio"] as? [[String: Any]] ?? []).compactMap { TimelineAudioSpec($0) }
    let clipsEnd = clips.map(\.end).max() ?? 0
    let duration = timelineDouble(args["duration"], fallback: clipsEnd)
    self.duration = duration > 0 ? duration : clipsEnd
  }

  let outputPath: String
  let width: Int
  let height: Int
  let frameRate: Int
  /// Movie length in seconds (the main track's length).
  let duration: Double
  let clips: [TimelineClipSpec]
  /// Draw order, bottom to top.
  let layers: [TimelineLayerSpec]
  let audio: [TimelineAudioSpec]
}

/// A main-track clip (`PlanClip`).
private struct TimelineClipSpec {
  init(_ values: [String: Any]) throws {
    guard let path = values["path"] as? String, !path.isEmpty else {
      throw timelineError("A timeline clip has no file.")
    }
    self.path = path
    isVideo = values["kind"] as? String == "video"
    start = timelineDouble(values["start"], fallback: 0)
    duration = max(0.04, timelineDouble(values["duration"], fallback: 3))
    overlapIn = max(0, timelineDouble(values["overlapIn"], fallback: 0))
    sourceStart = isVideo ? max(0, timelineDouble(values["sourceStart"], fallback: 0)) : 0
    speed = isVideo ? timelinePositive(values["speed"], fallback: 1) : 1
    sourceDuration = max(0, timelineDouble(values["sourceDuration"], fallback: duration * speed))
    cover = values["fit"] as? String == "cover"
    keys = timelineKeys(values["keys"]) { TimelineTransformKey($0) }
    settings = values["grade"] as? [String: Any] ?? [:]
    look = values["look"] as? [String: Any] ?? [:]
    filters = TimelineFilters(values["filters"] as? [String: Any])
  }

  let path: String
  let isVideo: Bool
  /// Timeline seconds.
  let start: Double
  let duration: Double
  /// Seconds this clip dissolves over the previous one.
  let overlapIn: Double
  /// Frame at local time `t` is source time `sourceStart + t × speed`.
  let sourceStart: Double
  let sourceDuration: Double
  let speed: Double
  /// Fill the canvas (cropping) instead of letterboxing.
  let cover: Bool
  /// Sorted; empty means identity.
  let keys: [TimelineTransformKey]
  let settings: [String: Any]
  let look: [String: Any]
  let filters: TimelineFilters

  var end: Double { start + duration }
}

/// A layer drawn over the main track (`PlanLayer`).
private struct TimelineLayerSpec {
  enum Kind: String {
    case video, image, color
  }

  init(_ values: [String: Any]) throws {
    guard let kind = Kind(rawValue: values["kind"] as? String ?? "") else {
      throw timelineError("A timeline layer has an unknown kind.")
    }
    self.kind = kind
    let path = values["path"] as? String
    if kind != .color, path?.isEmpty ?? true {
      throw timelineError("A timeline layer has no file.")
    }
    self.path = kind == .color ? nil : path
    // Unsigned 32-bit ARGB; values above Int32.max arrive as 64-bit numbers.
    let argb = UInt32(truncatingIfNeeded: (values["color"] as? NSNumber)?.int64Value ?? 0xFF00_0000)
    color = CIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255
    )
    colorAlpha = kind == .color ? Double(argb >> 24) / 255 : 1
    start = timelineDouble(values["start"], fallback: 0)
    duration = max(0, timelineDouble(values["duration"], fallback: 0))
    sourceStart = max(0, timelineDouble(values["sourceStart"], fallback: 0))
    speed = timelinePositive(values["speed"], fallback: 1)
    sourceDuration = max(0, timelineDouble(values["sourceDuration"], fallback: duration * speed))
    keys = timelineKeys(values["keys"]) { TimelineLayerKey($0) }
    maxWidth = keys.map(\.w).max() ?? 0
    maxHeight = keys.map(\.h).max() ?? 0
    grade = values["grade"] as? [String: Any]
    look = values["look"] as? [String: Any]
    filters = TimelineFilters(values["filters"] as? [String: Any])
  }

  let kind: Kind
  /// The video or image file; `nil` for colour layers.
  let path: String?
  /// Opaque fill of a colour layer; its alpha is [colorAlpha].
  let color: CIColor
  /// Multiplies the keyed opacity (1 for video and image layers).
  let colorAlpha: Double
  /// Timeline seconds; active for `start <= t < start + duration`.
  let start: Double
  let duration: Double
  let sourceStart: Double
  let sourceDuration: Double
  let speed: Double
  /// Sorted; at least one in a valid plan.
  let keys: [TimelineLayerKey]
  /// The largest rect the layer is drawn at, in output pixels.
  let maxWidth: Double
  let maxHeight: Double
  /// `nil` leaves the source's colours.
  let grade: [String: Any]?
  let look: [String: Any]?
  let filters: TimelineFilters

  var end: Double { start + duration }
}

/// One sound segment of the mix (`PlanAudio`).
private struct TimelineAudioSpec {
  init?(_ values: [String: Any]) {
    guard let path = values["path"] as? String, !path.isEmpty else { return nil }
    self.path = path
    lane = max(0, timelineInt(values["lane"], fallback: 0))
    start = timelineDouble(values["start"], fallback: 0)
    sourceStart = max(0, timelineDouble(values["sourceStart"], fallback: 0))
    sourceDuration = max(0, timelineDouble(values["sourceDuration"], fallback: 0))
    speed = timelinePositive(values["speed"], fallback: 1)
    volume = min(1, max(0, timelineDouble(values["volume"], fallback: 1)))
    fadeIn = max(0, timelineDouble(values["fadeIn"], fallback: 0))
    fadeOut = max(0, timelineDouble(values["fadeOut"], fallback: 0))
  }

  let path: String
  /// Mixer lane; segments on one lane never overlap.
  let lane: Int
  /// Timeline seconds.
  let start: Double
  /// Source seconds read, played at [speed] with the pitch kept.
  let sourceStart: Double
  let sourceDuration: Double
  let speed: Double
  let volume: Double
  /// Linear gain ramps in timeline seconds at the segment's ends.
  let fadeIn: Double
  let fadeOut: Double

  var duration: Double { sourceDuration / speed }
  var end: Double { start + duration }

  /// Gain at timeline [time]: the volume times both fade ramps.
  func gain(at time: Double) -> Double {
    var gain = volume
    if fadeIn > 0 {
      gain *= min(1, max(0, (time - start) / fadeIn))
    }
    if fadeOut > 0 {
      gain *= min(1, max(0, (end - time) / fadeOut))
    }
    return gain
  }
}

/// Per-pixel filters of a clip or layer (`PlanFilters`), in output pixels.
private struct TimelineFilters {
  /// Sigmas below this change nothing visible.
  static let minSigma = 0.01

  init(_ values: [String: Any]?) {
    let values = values ?? [:]
    let matrix = (values["colorMatrix"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue }
    if let matrix = matrix, matrix.count == 20, matrix.allSatisfy({ $0.isFinite }) {
      colorMatrix = matrix
    } else {
      colorMatrix = nil
    }
    blurSigma = max(0, timelineDouble(values["blurSigma"], fallback: 0))
    sharpen = max(0, timelineDouble(values["sharpen"], fallback: 0))
    sharpenSigma = max(0, timelineDouble(values["sharpenSigma"], fallback: 0))
    grain = max(0, timelineDouble(values["grain"], fallback: 0))
  }

  /// 4×5 row-major, offsets in 0…1; `nil` for none.
  let colorMatrix: [Double]?
  let blurSigma: Double
  let sharpen: Double
  let sharpenSigma: Double
  /// Standard deviation of the added noise, in 0…1 units.
  let grain: Double

  var sharpens: Bool { sharpen > 0.001 && sharpenSigma > Self.minSigma }

  /// Whether a blur or sharpen needs the image at output resolution.
  var hasSpatial: Bool { blurSigma > Self.minSigma || sharpens }
}

// MARK: - Keys

/// A key of a piecewise-linear animation at local time `t`.
private protocol TimelineKeyframe {
  var t: Double { get }
  static func mix(_ a: Self, _ b: Self, _ fraction: Double) -> Self
}

/// Main-clip transform (`TransformKey`): about the canvas centre, scale, then
/// rotate clockwise by `rotation` degrees, then move by (x, y), y down.
private struct TimelineTransformKey: TimelineKeyframe {
  static let identity = TimelineTransformKey(t: 0, scale: 1, x: 0, y: 0, rotation: 0)

  init(t: Double, scale: Double, x: Double, y: Double, rotation: Double) {
    self.t = t
    self.scale = scale
    self.x = x
    self.y = y
    self.rotation = rotation
  }

  init(_ values: [String: Any]) {
    self.init(
      t: timelineDouble(values["t"], fallback: 0),
      scale: timelineDouble(values["scale"], fallback: 1),
      x: timelineDouble(values["x"], fallback: 0),
      y: timelineDouble(values["y"], fallback: 0),
      rotation: timelineDouble(values["rotation"], fallback: 0)
    )
  }

  let t: Double
  let scale: Double
  let x: Double
  let y: Double
  let rotation: Double

  static func mix(_ a: Self, _ b: Self, _ fraction: Double) -> Self {
    func lerp(_ from: Double, _ to: Double) -> Double { from + (to - from) * fraction }
    return Self(
      t: lerp(a.t, b.t),
      scale: lerp(a.scale, b.scale),
      x: lerp(a.x, b.x),
      y: lerp(a.y, b.y),
      rotation: lerp(a.rotation, b.rotation)
    )
  }
}

/// Layer placement (`LayerKey`): the unrotated rect in output pixels from the
/// top-left, rotated clockwise about its centre, drawn with `opacity`.
private struct TimelineLayerKey: TimelineKeyframe {
  init(t: Double, x: Double, y: Double, w: Double, h: Double, rotation: Double, opacity: Double) {
    self.t = t
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.rotation = rotation
    self.opacity = opacity
  }

  init(_ values: [String: Any]) {
    self.init(
      t: timelineDouble(values["t"], fallback: 0),
      x: timelineDouble(values["x"], fallback: 0),
      y: timelineDouble(values["y"], fallback: 0),
      w: timelineDouble(values["w"], fallback: 0),
      h: timelineDouble(values["h"], fallback: 0),
      rotation: timelineDouble(values["rotation"], fallback: 0),
      opacity: timelineDouble(values["opacity"], fallback: 1)
    )
  }

  let t: Double
  let x: Double
  let y: Double
  let w: Double
  let h: Double
  let rotation: Double
  let opacity: Double

  static func mix(_ a: Self, _ b: Self, _ fraction: Double) -> Self {
    func lerp(_ from: Double, _ to: Double) -> Double { from + (to - from) * fraction }
    return Self(
      t: lerp(a.t, b.t),
      x: lerp(a.x, b.x),
      y: lerp(a.y, b.y),
      w: lerp(a.w, b.w),
      h: lerp(a.h, b.h),
      rotation: lerp(a.rotation, b.rotation),
      opacity: lerp(a.opacity, b.opacity)
    )
  }
}

/// Linear interpolation between the keys around [time], clamped to the first
/// and last key outside them; `nil` without keys.
private func evaluateKeys<Key: TimelineKeyframe>(_ keys: [Key], at time: Double) -> Key? {
  guard let first = keys.first, let last = keys.last else { return nil }
  if time <= first.t { return first }
  for index in 1..<keys.count where time <= keys[index].t {
    let a = keys[index - 1]
    let b = keys[index]
    let span = b.t - a.t
    return Key.mix(a, b, span <= 0 ? 1 : (time - a.t) / span)
  }
  return last
}

/// The keys in [value] (a list of maps), sorted by time.
private func timelineKeys<Key: TimelineKeyframe>(_ value: Any?, _ make: ([String: Any]) -> Key) -> [Key] {
  let raw = value as? [Any] ?? []
  return raw.compactMap { $0 as? [String: Any] }.map(make).sorted { $0.t < $1.t }
}

// MARK: - Values

private func timelineError(_ message: String) -> NSError {
  NSError(domain: AquaMediaPipeline.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

/// Audio times use a 48 kHz timescale, the mix's sample rate.
private func timelineTime(_ seconds: Double) -> CMTime {
  CMTime(seconds: seconds, preferredTimescale: 48_000)
}

private func timelineDouble(_ value: Any?, fallback: Double) -> Double {
  if let number = value as? NSNumber {
    let double = number.doubleValue
    return double.isFinite ? double : fallback
  }
  return fallback
}

private func timelinePositive(_ value: Any?, fallback: Double) -> Double {
  let number = timelineDouble(value, fallback: fallback)
  return number > 0 ? number : fallback
}

private func timelineInt(_ value: Any?, fallback: Int) -> Int {
  (value as? NSNumber)?.intValue ?? fallback
}
