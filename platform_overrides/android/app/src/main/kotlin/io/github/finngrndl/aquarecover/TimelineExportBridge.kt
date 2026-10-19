package io.github.finngrndl.aquarecover

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.opengl.GLES20
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Pair
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.SingleColorLut
import androidx.media3.effect.SpeedChangeEffect
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Random
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Renders an AquaRecover timeline plan (contract v2) on the `aqua_recover/timeline` channel with
 * Media3 Transformer 1.8.0.
 *
 * The main track is one sequence of photos and clips laid out on the plan's timeline. Media3
 * sequences cannot overlap items, so each crossfade is cut at its midpoint and renders as a dip
 * through black. Every item gets its speed, its baked colour table (grade, look and colour
 * matrix), the fit, blur, sharpen, grain, the key transform, the dip and the image and colour
 * layers above it ([LayerOverlay]s in [OverlayEffect]s).
 *
 * Video layers need their own decoders, so only a plan with video layers becomes a multi-sequence
 * composition: an invisible image clock first (the compositor's primary input sets the output
 * timestamps, at the plan's frame rate, and is drawn on top, here fully transparent), then one
 * sequence per video-layer slot from top to bottom, then the main track. [LayerCompositorSettings]
 * places every slot frame from its layer's keys. An image or colour layer that overlaps a video
 * layer in time is drawn by a composition-level overlay instead, above everything.
 *
 * Audio comes only from `audio[]`: one audio-only sequence per lane with gaps, a stereo downmix
 * for surround sources, Sonic for speed (pitch kept) and a [GainProcessor] for volume and fades.
 * The main track adds forced silence so the output always has an audio track.
 *
 * Approximations where Media3 1.8.0 cannot follow the plan exactly: a crossfade is a dip through
 * black of the same length (the audio still crossfades); grain on image layers is a fixed pattern;
 * blur, sharpen and grain on image layers above 2048 × 2048 bitmap pixels are skipped; an image or
 * colour layer that overlaps an earlier video layer is drawn above every video layer; video gaps
 * shorter than 40 ms in a video-layer slot are dropped, so such a layer may start up to 40 ms early.
 *
 * Time base, read from the 1.8.0 sources: `VideoSampleExporter` registers every item with
 * `offsetToAddUs`, the sum of the effect-adjusted durations of the earlier items in its sequence
 * (zero for the first item of a normal export), and the texture managers add it to the decoder or
 * image timestamps before the item's effects run. Item effects therefore see sequence time, and
 * effects after a [SpeedChangeEffect] see the sped-up time. Every sequence here is laid out on the
 * plan's timeline, so that is plan time. The single-input graph appends composition effects to
 * each item's chain (same time); the multi-input graph runs them on the compositor output, whose
 * timestamps are the primary's (the clock: plan time again). Compositor settings are evaluated
 * once per input frame, with that frame's own timestamp.
 */
@OptIn(UnstableApi::class)
class TimelineExportBridge private constructor(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var transformer: Transformer? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "stillFrame" -> stillFrame(call, result)
            "renderTimeline" -> render(call, result)
            "cancelTimeline" -> {
                transformer?.cancel()
                transformer = null
                pendingResult?.error("CANCELLED", "Timeline export was cancelled.", null)
                pendingResult = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** A downscaled JPEG of a photo, for baking its colour table in Dart. */
    private fun stillFrame(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val maxDimension = (call.argument<Int>("maxDimension") ?: 384).coerceIn(64, 2048)
        if (path.isNullOrBlank() || !File(path).isFile) {
            result.error("BAD_ARGS", "path must be an existing file", null)
            return
        }
        worker.execute {
            try {
                val bitmap = decodeScaled(File(path), maxDimension)
                    ?: throw IllegalStateException("Could not decode ${File(path).name}.")
                val bytes = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, bytes)
                bitmap.recycle()
                mainHandler.post { result.success(bytes.toByteArray()) }
            } catch (error: Throwable) {
                mainHandler.post { result.error("STILL_DECODE_FAILED", error.message, null) }
            }
        }
    }

    private fun decodeScaled(file: File, maxDimension: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val source = ImageDecoder.createSource(file)
            return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                val scale = min(1f, maxDimension.toFloat() / max(info.size.width, info.size.height))
                decoder.setTargetSize(
                    max(1, (info.size.width * scale).toInt()),
                    max(1, (info.size.height * scale).toInt()),
                )
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
        return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun render(call: MethodCall, result: MethodChannel.Result) {
        if (transformer != null || pendingResult != null) {
            result.error("BUSY", "Another timeline export is still running.", null)
            return
        }
        val outputPath = call.argument<String>("outputPath")
        if (outputPath.isNullOrBlank()) {
            result.error("BAD_ARGS", "outputPath and clips are required", null)
            return
        }
        val plan = try {
            TimelinePlan.parse(call)
        } catch (error: IllegalArgumentException) {
            result.error("BAD_ARGS", error.message, null)
            return
        }

        // Probing audio files and building the composition read the disk, so they run on the
        // worker; Transformer itself is started on the main looper.
        pendingResult = result
        worker.execute {
            try {
                val composition = buildComposition(plan)
                File(outputPath).parentFile?.mkdirs()
                File(outputPath).delete()
                mainHandler.post { if (pendingResult === result) start(composition, outputPath) }
            } catch (error: Throwable) {
                mainHandler.post {
                    if (pendingResult === result) {
                        finish { it.error("TIMELINE_RENDER_FAILED", error.message, null) }
                    }
                }
            }
        }
    }

    private fun start(composition: Composition, outputPath: String) {
        try {
            val built = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        finish { it.success(outputPath) }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        File(outputPath).delete()
                        finish { it.error("TIMELINE_RENDER_FAILED", exportException.message, null) }
                    }
                })
                .build()
            transformer = built
            built.start(composition, outputPath)
            pollProgress(built)
        } catch (error: Throwable) {
            finish { it.error("TIMELINE_RENDER_FAILED", error.message, null) }
        }
    }

    /**
     * The single-sequence graph when the plan has no video layers (it rejects custom compositor
     * settings), otherwise clock + video-layer slots + main track through the compositor. Audio
     * lanes come last so they never shift the compositor's input indices.
     */
    private fun buildComposition(plan: TimelinePlan): Composition {
        val bands = LayerBands.assign(plan.layers)
        val pool = OverlayPool(plan.width, plan.height)
        val sequences = ArrayList<EditedMediaItemSequence>()
        val builder: Composition.Builder
        if (bands.slots.isEmpty()) {
            sequences.add(mainSequence(plan, bands.main, pool, opaque = false))
            sequences.addAll(audioSequences(plan.audio))
            builder = Composition.Builder(sequences)
        } else {
            sequences.add(clockSequence(plan))
            val placements = ArrayList<List<SlotEntry>>()
            for (slot in bands.slots.asReversed()) {
                val entries = ArrayList<SlotEntry>()
                sequences.add(slotSequence(plan, slot, entries))
                placements.add(entries)
            }
            sequences.add(mainSequence(plan, bands.main, pool, opaque = true))
            sequences.addAll(audioSequences(plan.audio))
            val effects = ArrayList<Effect>()
            effects.add(
                Presentation.createForWidthAndHeight(plan.width, plan.height, Presentation.LAYOUT_SCALE_TO_FIT),
            )
            effects.addAll(pool.effects(bands.composition))
            builder = Composition.Builder(sequences)
                .setVideoCompositorSettings(LayerCompositorSettings(plan.width, plan.height, placements))
                .setEffects(Effects(emptyList(), effects))
        }
        return builder.setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL).build()
    }

    /**
     * The photos and clips. Item i plays its local time `[overlapIn / 2, duration - nextOverlap / 2)`,
     * so it starts in the sequence where the plan puts that moment and its effects can use the
     * sequence time directly.
     */
    private fun mainSequence(
        plan: TimelinePlan,
        layers: List<PlanLayer>,
        pool: OverlayPool,
        opaque: Boolean,
    ): EditedMediaItemSequence {
        val builder = EditedMediaItemSequence.Builder().experimentalSetForceAudioTrack(true)
        var positionUs = 0L
        var count = 0
        plan.clips.forEachIndexed { index, clip ->
            val nextOverlap = plan.clips.getOrNull(index + 1)?.overlapIn ?: 0.0
            val localStart = clip.overlapIn / 2
            val localEnd = clip.duration - nextOverlap / 2
            val playedUs: Long
            val mediaItem: MediaItem
            if (clip.isVideo) {
                val spanUs = toUs((localEnd - localStart) * clip.speed)
                playedUs = durationAtSpeed(spanUs, clip.speed)
                mediaItem = clippedMediaItem(clip.path, toUs(clip.sourceStart + localStart * clip.speed), spanUs)
            } else {
                playedUs = toUs(localEnd - localStart)
                mediaItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(File(clip.path)))
                    .setImageDurationMs(max(1L, playedUs / 1000))
                    .build()
            }
            if (playedUs < MIN_ITEM_US) return@forEachIndexed

            val endUs = positionUs + playedUs
            val effects = ArrayList<Effect>()
            if (clip.isVideo && clip.speed != 1.0) effects.add(SpeedChangeEffect(clip.speed.toFloat()))
            colourEffect(clip.table, clip.filters)?.let { effects.add(it) }
            // Filters work in canvas pixels. A contained frame is first scaled without its letterbox
            // so blur and sharpen do not pull the black bars into the picture.
            val separateFit = !clip.cover && clip.filters.isSpatial
            effects.add(
                if (separateFit) {
                    ContainSize(plan.width, plan.height)
                } else {
                    Presentation.createForWidthAndHeight(
                        plan.width,
                        plan.height,
                        if (clip.cover) Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP else Presentation.LAYOUT_SCALE_TO_FIT,
                    )
                },
            )
            effects.addAll(filterEffects(clip.filters))
            if (separateFit) {
                effects.add(
                    Presentation.createForWidthAndHeight(plan.width, plan.height, Presentation.LAYOUT_SCALE_TO_FIT),
                )
            }
            if (clip.keys.isNotEmpty()) {
                effects.add(KeyTransform(clip.keys, plan.width, plan.height, positionUs, localStart))
            }
            val fadeInUs = toUs(clip.overlapIn / 2)
            val fadeOutUs = toUs(nextOverlap / 2)
            if (fadeInUs > 0 || fadeOutUs > 0) effects.add(DipToBlack(positionUs, endUs, fadeInUs, fadeOutUs))
            val above = layers.filter {
                it.startUs < endUs + LAYER_MARGIN_US && it.endUs > positionUs - LAYER_MARGIN_US
            }
            if (above.isNotEmpty()) {
                // In the compositor the main frame is blended by its alpha, which the overlay shader
                // leaves premultiplied where the frame was transparent (letterbox, moved keys).
                if (opaque) effects.add(OpaqueEffect())
                effects.addAll(pool.effects(above))
            }

            val item = EditedMediaItem.Builder(mediaItem)
                .setEffects(Effects(emptyList(), effects))
                .setRemoveAudio(true)
            if (!clip.isVideo) item.setDurationUs(playedUs).setFrameRate(plan.fps)
            builder.addItem(item.build())
            positionUs = endUs
            count++
        }
        if (count == 0) throw IllegalArgumentException("The timeline has no playable clips.")
        return builder.build()
    }

    /**
     * A transparent 1×1 image lasting the whole plan. As the first sequence it is the compositor's
     * primary input, so the output has the plan's frame rate and length.
     */
    private fun clockSequence(plan: TimelinePlan): EditedMediaItemSequence {
        val file = File(context.cacheDir, "timeline_clock.png")
        val pixel = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        FileOutputStream(file).use { pixel.compress(Bitmap.CompressFormat.PNG, 100, it) }
        pixel.recycle()
        val durationUs = max(MIN_ITEM_US, toUs(plan.duration))
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(file))
            .setImageDurationMs(max(1L, durationUs / 1000))
            .build()
        val item = EditedMediaItem.Builder(mediaItem)
            .setDurationUs(durationUs)
            .setFrameRate(plan.fps)
            .build()
        return EditedMediaItemSequence.Builder(item).build()
    }

    /**
     * One compositor slot: its video layers in time order with gaps between them and up to the end
     * (an input that ends early keeps showing its last frame). Gap frames are opaque black, so the
     * compositor hides every frame outside the [entries] it records.
     */
    private fun slotSequence(
        plan: TimelinePlan,
        layers: List<PlanLayer>,
        entries: MutableList<SlotEntry>,
    ): EditedMediaItemSequence {
        val builder = EditedMediaItemSequence.Builder().experimentalSetForceVideoTrack(true)
        var positionUs = 0L
        for (layer in layers.sortedBy { it.start }) {
            val gapUs = layer.startUs - positionUs
            if (gapUs >= MIN_VIDEO_GAP_US) {
                builder.addGap(gapUs)
                positionUs += gapUs
            }
            val spanUs = toUs(layer.sourceDuration)
            val playedUs = durationAtSpeed(spanUs, layer.speed)
            if (playedUs < MIN_ITEM_US) continue
            val textureWidth = ceil(layer.maxWidth).toInt().coerceIn(2, MAX_TEXTURE_SIDE)
            val textureHeight = ceil(layer.maxHeight).toInt().coerceIn(2, MAX_TEXTURE_SIDE)

            val effects = ArrayList<Effect>()
            if (layer.speed != 1.0) effects.add(SpeedChangeEffect(layer.speed.toFloat()))
            colourEffect(layer.table, layer.filters)?.let { effects.add(it) }
            effects.add(
                Presentation.createForWidthAndHeight(textureWidth, textureHeight, Presentation.LAYOUT_STRETCH_TO_FIT),
            )
            effects.addAll(filterEffects(layer.filters))
            val path = layer.path ?: continue
            builder.addItem(
                EditedMediaItem.Builder(clippedMediaItem(path, toUs(layer.sourceStart), spanUs))
                    .setRemoveAudio(true)
                    .setEffects(Effects(emptyList(), effects))
                    .build(),
            )
            entries.add(SlotEntry(layer, positionUs, positionUs + playedUs, textureWidth, textureHeight))
            positionUs += playedUs
        }
        val tailUs = toUs(plan.duration) - positionUs
        if (tailUs >= MIN_VIDEO_GAP_US) builder.addGap(tailUs)
        return builder.build()
    }

    /**
     * One audio-only sequence per lane. The plan's lane is kept when it is free; a segment that
     * would overlap the one before it moves to another lane. Segments whose file has no audio
     * track are skipped.
     */
    private fun audioSequences(audio: List<PlanAudio>): List<EditedMediaItemSequence> {
        val hasAudio = HashMap<String, Boolean>()
        val lanes = ArrayList<ArrayList<PlanAudio>>()
        val laneEnds = ArrayList<Double>()
        for (segment in audio.sortedBy { it.start }) {
            val playable = hasAudio.getOrPut(segment.path) { probeAudio(segment.path) }
            if (!playable || segment.duration <= 0 || segment.sourceDuration <= 0) continue
            while (lanes.size <= segment.lane) {
                lanes.add(ArrayList())
                laneEnds.add(Double.NEGATIVE_INFINITY)
            }
            var lane = segment.lane
            if (laneEnds[lane] > segment.start + LANE_TOLERANCE) {
                lane = laneEnds.indexOfFirst { it <= segment.start + LANE_TOLERANCE }
                if (lane < 0) {
                    lanes.add(ArrayList())
                    laneEnds.add(Double.NEGATIVE_INFINITY)
                    lane = lanes.lastIndex
                }
            }
            lanes[lane].add(segment)
            laneEnds[lane] = segment.start + segment.duration
        }

        return lanes.filter { it.isNotEmpty() }.map { lane ->
            // Forcing the audio track lets a lane start with a gap.
            val builder = EditedMediaItemSequence.Builder().experimentalSetForceAudioTrack(true)
            var positionUs = 0L
            for (segment in lane) {
                val gapUs = toUs(segment.start) - positionUs
                if (gapUs >= MIN_AUDIO_GAP_US) {
                    builder.addGap(gapUs)
                    positionUs += gapUs
                }
                val spanUs = toUs(segment.sourceDuration)
                val processors = ArrayList<AudioProcessor>()
                // Media3 only converts mono and stereo to the output layout, so surround tracks
                // are folded to stereo first (mono and stereo pass through untouched).
                processors.add(downmixToStereo())
                if (segment.speed != 1.0) {
                    processors.add(
                        SonicAudioProcessor().apply {
                            setSpeed(segment.speed.toFloat())
                            setPitch(1f)
                        },
                    )
                }
                // After Sonic, so the gain sees timeline time from the segment start.
                processors.add(GainProcessor(FadeGain(segment)))
                builder.addItem(
                    EditedMediaItem.Builder(clippedMediaItem(segment.path, toUs(segment.sourceStart), spanUs))
                        .setRemoveVideo(true)
                        .setEffects(Effects(processors, emptyList()))
                        .build(),
                )
                positionUs += durationAtSpeed(spanUs, segment.speed)
            }
            builder.build()
        }
    }

    /** Identity for mono and stereo, constant-power stereo downmix for 3 to 6 channels. */
    private fun downmixToStereo(): ChannelMixingAudioProcessor {
        val mixer = ChannelMixingAudioProcessor()
        mixer.putChannelMixingMatrix(ChannelMixingMatrix.createForConstantGain(1, 1))
        mixer.putChannelMixingMatrix(ChannelMixingMatrix.createForConstantGain(2, 2))
        for (channels in 3..6) {
            mixer.putChannelMixingMatrix(ChannelMixingMatrix.createForConstantPower(channels, 2))
        }
        return mixer
    }

    private fun probeAudio(path: String): Boolean {
        if (!File(path).isFile) return false
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
        } catch (error: Exception) {
            false
        } finally {
            try {
                retriever.release()
            } catch (ignored: Exception) {
            }
        }
    }

    private fun pollProgress(active: Transformer) {
        val holder = ProgressHolder()
        mainHandler.postDelayed(object : Runnable {
            override fun run() {
                if (transformer !== active) return
                if (active.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    channel.invokeMethod("progress", holder.progress / 100.0)
                }
                mainHandler.postDelayed(this, 500)
            }
        }, 500)
    }

    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        val result = pendingResult
        transformer = null
        pendingResult = null
        if (result != null) reply(result)
    }

    companion object {
        private const val CHANNEL = "aqua_recover/timeline"

        fun register(context: Context, messenger: BinaryMessenger) {
            val channel = MethodChannel(messenger, CHANNEL)
            channel.setMethodCallHandler(TimelineExportBridge(context.applicationContext, channel))
        }
    }
}

private const val CONTRACT_VERSION = 2

/** Items and gaps shorter than this are dropped. */
private const val MIN_ITEM_US = 1_000L

/** Shorter video gaps may produce no gap frame (gap frames run at 30 fps), so they are skipped. */
private const val MIN_VIDEO_GAP_US = 40_000L

private const val MIN_AUDIO_GAP_US = 1_000L

/** Layers this close to a main item are attached to it, to absorb rounding. */
private const val LAYER_MARGIN_US = 500_000L

/** Seven overlay samplers plus the frame fit the eight texture units OpenGL ES 2 guarantees. */
private const val OVERLAYS_PER_EFFECT = 7

/** Media3 checks textures against GL_MAX_TEXTURE_SIZE; 4096 is safe on current devices. */
private const val MAX_TEXTURE_SIDE = 4096

private const val MIN_SIGMA = 0.05f

private const val LANE_TOLERANCE = 0.001

/** [GainProcessor] needs a unity region wherever the gain is exactly 1, so ramps stop just short. */
private const val ALMOST_ONE = 0.9999999f

private fun toUs(seconds: Double): Long = (seconds * 1_000_000).roundToLong()

/**
 * The duration Media3 assigns to [spanUs] of media played at [speed]: `SpeedChangeEffect` gets the
 * speed as a float and `SpeedProviderUtil` floors the result, so this matches it to the microsecond.
 */
private fun durationAtSpeed(spanUs: Long, speed: Double): Long =
    if (speed == 1.0) spanUs else floor(spanUs / speed.toFloat().toDouble()).toLong()

@OptIn(UnstableApi::class)
private fun clippedMediaItem(path: String, startUs: Long, spanUs: Long): MediaItem {
    val start = max(0L, startUs)
    return MediaItem.Builder()
        .setUri(Uri.fromFile(File(path)))
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder()
                .setStartPositionUs(start)
                .setEndPositionUs(start + spanUs)
                .build(),
        )
        .build()
}

/** The baked colour table, or the colour matrix when no table was sent. */
@OptIn(UnstableApi::class)
private fun colourEffect(table: ColorTable?, filters: PlanFilters): Effect? =
    table?.toEffect() ?: filters.colorMatrix?.let { ColorMatrixEffect(it) }

/** Blur, unsharp mask and grain, in that order; sigmas are in pixels of the current frame. */
@OptIn(UnstableApi::class)
private fun filterEffects(filters: PlanFilters): List<Effect> {
    val effects = ArrayList<Effect>()
    if (filters.blurSigma > MIN_SIGMA) effects.add(GaussianBlur(filters.blurSigma, 3f))
    if (filters.sharpen > 0f && filters.sharpenSigma > MIN_SIGMA) {
        effects.add(SharpenEffect(filters.sharpen, filters.sharpenSigma))
    }
    if (filters.grain > 0f) effects.add(GrainEffect(filters.grain))
    return effects
}

/**
 * Linear interpolation of [keys] (rows starting with their local time `t`, sorted) at [t],
 * clamped to the first and last key.
 */
private fun evaluateKeys(keys: List<DoubleArray>, t: Double): DoubleArray {
    val first = keys.first()
    if (keys.size == 1 || t <= first[0]) return first
    val last = keys.last()
    if (t >= last[0]) return last
    var low = 0
    var high = keys.lastIndex
    while (high - low > 1) {
        val mid = (low + high) ushr 1
        if (keys[mid][0] <= t) low = mid else high = mid
    }
    val a = keys[low]
    val b = keys[high]
    val span = b[0] - a[0]
    val f = if (span > 0) (t - a[0]) / span else 1.0
    return DoubleArray(a.size) { a[it] + (b[it] - a[it]) * f }
}

private fun Map<*, *>.number(key: String, fallback: Double = 0.0): Double =
    (this[key] as? Number)?.toDouble()?.takeIf { it.isFinite() } ?: fallback

private fun Map<*, *>.keyRows(fields: Array<String>, defaults: DoubleArray): List<DoubleArray> =
    (this["keys"] as? List<*>).orEmpty()
        .mapNotNull { raw ->
            val key = raw as? Map<*, *> ?: return@mapNotNull null
            DoubleArray(fields.size) { key.number(fields[it], defaults[it]) }
        }
        .sortedBy { it[0] }

private fun Map<*, *>.speed(): Double {
    val speed = number("speed", 1.0).coerceIn(0.1, 10.0)
    return if (abs(speed - 1) < 1e-4) 1.0 else speed
}

/** The parsed `renderTimeline` arguments; times in seconds, positions in output pixels. */
private class TimelinePlan(
    val width: Int,
    val height: Int,
    val fps: Int,
    val duration: Double,
    val clips: List<PlanClip>,
    val layers: List<PlanLayer>,
    val audio: List<PlanAudio>,
) {
    companion object {
        /** Throws [IllegalArgumentException] for arguments that cannot be rendered. */
        fun parse(call: MethodCall): TimelinePlan {
            val version = call.argument<Int>("version")
            require(version == null || version == CONTRACT_VERSION) {
                "Unsupported timeline contract version $version."
            }
            val rawClips = call.argument<List<Map<String, Any?>>>("clips")
            if (rawClips.isNullOrEmpty()) throw IllegalArgumentException("outputPath and clips are required")
            val width = call.argument<Int>("width") ?: 1920
            val height = call.argument<Int>("height") ?: 1080
            require(width in 16..MAX_TEXTURE_SIDE && height in 16..MAX_TEXTURE_SIDE) { "Unsupported output size." }
            val clips = rawClips.map { PlanClip.parse(it) }
            val layers = call.argument<List<Map<String, Any?>>>("layers").orEmpty().mapNotNull { PlanLayer.parse(it) }
            val audio = call.argument<List<Map<String, Any?>>>("audio").orEmpty().mapNotNull { PlanAudio.parse(it) }
            val clipsEnd = clips.maxOf { it.start + it.duration }
            val duration = (call.argument<Number>("duration")?.toDouble() ?: clipsEnd).takeIf { it > 0 } ?: clipsEnd
            return TimelinePlan(
                width = width,
                height = height,
                fps = (call.argument<Int>("frameRate") ?: 30).coerceIn(12, 60),
                duration = duration,
                clips = clips,
                layers = layers,
                audio = audio,
            )
        }
    }
}

/** A main-track photo or clip; [keys] rows are `[t, scale, x, y, rotation]`. */
private class PlanClip(
    val path: String,
    val isVideo: Boolean,
    val start: Double,
    val duration: Double,
    val overlapIn: Double,
    val sourceStart: Double,
    val speed: Double,
    val cover: Boolean,
    val keys: List<DoubleArray>,
    val filters: PlanFilters,
    val table: ColorTable?,
) {
    companion object {
        fun parse(map: Map<String, Any?>): PlanClip {
            val path = map["path"] as? String
            if (path.isNullOrBlank()) throw IllegalArgumentException("A clip has no file.")
            require(File(path).isFile) { "The file of a clip is missing: ${File(path).name}." }
            val keys = map.keyRows(arrayOf("t", "scale", "x", "y", "rotation"), doubleArrayOf(0.0, 1.0, 0.0, 0.0, 0.0))
            return PlanClip(
                path = path,
                isVideo = map["kind"] == "video",
                start = map.number("start"),
                duration = map.number("duration", 3.0),
                overlapIn = max(0.0, map.number("overlapIn")),
                sourceStart = max(0.0, map.number("sourceStart")),
                speed = map.speed(),
                cover = map["fit"]?.let { it == "cover" } ?: keys.isNotEmpty(),
                keys = keys,
                filters = PlanFilters.parse(map["filters"]),
                table = ColorTable.parse(map),
            )
        }
    }
}

/**
 * A layer above the main track; [keys] rows are `[t, x, y, w, h, rotation, opacity]` with the
 * rect's top-left corner, clockwise degrees and t local to [start].
 */
private class PlanLayer(
    val kind: String,
    val path: String?,
    val color: Int,
    val start: Double,
    val duration: Double,
    val sourceStart: Double,
    val sourceDuration: Double,
    val speed: Double,
    val keys: List<DoubleArray>,
    val filters: PlanFilters,
    val table: ColorTable?,
) {
    val startUs = toUs(start)
    val endUs = toUs(start + duration)
    val maxWidth = keys.maxOf { it[3] }
    val maxHeight = keys.maxOf { it[4] }

    fun overlaps(other: PlanLayer): Boolean =
        start < other.start + other.duration && other.start < start + duration

    fun keyAt(timeUs: Long): DoubleArray = evaluateKeys(keys, (timeUs - startUs) / 1e6)

    companion object {
        /** Null for a layer with nothing to draw. */
        fun parse(map: Map<String, Any?>): PlanLayer? {
            val kind = map["kind"] as? String ?: return null
            val keys = map.keyRows(
                arrayOf("t", "x", "y", "w", "h", "rotation", "opacity"),
                doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0),
            )
            val duration = map.number("duration")
            if (keys.isEmpty() || duration <= 0) return null
            val path = map["path"] as? String
            when (kind) {
                "video", "image" -> {
                    require(!path.isNullOrBlank() && File(path).isFile) {
                        "The file of layer ${map["id"]} is missing."
                    }
                }
                "color" -> if (map["color"] !is Number) return null
                else -> return null
            }
            val speed = map.speed()
            return PlanLayer(
                kind = kind,
                path = path,
                color = (map["color"] as? Number)?.toLong()?.toInt() ?: 0,
                start = map.number("start"),
                duration = duration,
                sourceStart = max(0.0, map.number("sourceStart")),
                sourceDuration = map.number("sourceDuration", duration * speed),
                speed = speed,
                keys = keys,
                filters = PlanFilters.parse(map["filters"]),
                table = ColorTable.parse(map),
            )
        }
    }
}

/** An audio segment; it plays `sourceDuration / speed` seconds of its file from [start]. */
private class PlanAudio(
    val path: String,
    val lane: Int,
    val start: Double,
    val duration: Double,
    val sourceStart: Double,
    val sourceDuration: Double,
    val speed: Double,
    val volume: Float,
    val fadeIn: Double,
    val fadeOut: Double,
) {
    companion object {
        fun parse(map: Map<String, Any?>): PlanAudio? {
            val path = map["path"] as? String
            if (path.isNullOrBlank()) return null
            val speed = map.speed()
            val sourceDuration = map.number("sourceDuration")
            return PlanAudio(
                path = path,
                lane = map.number("lane").toInt().coerceIn(0, 64),
                start = max(0.0, map.number("start")),
                duration = map.number("duration", sourceDuration / speed),
                sourceStart = max(0.0, map.number("sourceStart")),
                sourceDuration = sourceDuration,
                speed = speed,
                volume = map.number("volume", 1.0).toFloat().coerceIn(0f, 1f),
                fadeIn = max(0.0, map.number("fadeIn")),
                fadeOut = max(0.0, map.number("fadeOut")),
            )
        }
    }
}

/** `PlanFilters`; [colorMatrix] is the row-major 4×5 matrix with offsets in 0…1. */
private class PlanFilters(
    val colorMatrix: FloatArray?,
    val blurSigma: Float,
    val sharpen: Float,
    val sharpenSigma: Float,
    val grain: Float,
) {
    /** Whether a filter looks at neighbouring pixels or adds noise. */
    val isSpatial: Boolean
        get() = blurSigma > MIN_SIGMA || (sharpen > 0f && sharpenSigma > MIN_SIGMA) || grain > 0f

    companion object {
        fun parse(raw: Any?): PlanFilters {
            val map = raw as? Map<*, *> ?: return PlanFilters(null, 0f, 0f, 0f, 0f)
            val matrix = (map["colorMatrix"] as? List<*>)?.takeIf { it.size == 20 }
            return PlanFilters(
                colorMatrix = matrix?.let { list -> FloatArray(20) { (list[it] as? Number)?.toFloat() ?: 0f } },
                blurSigma = max(0.0, map.number("blurSigma")).toFloat(),
                sharpen = max(0.0, map.number("sharpen")).toFloat(),
                sharpenSigma = max(0.0, map.number("sharpenSigma")).toFloat(),
                grain = max(0.0, map.number("grain")).toFloat(),
            )
        }
    }
}

/** A baked `.cube`-ordered colour table (red fastest) of `0xFFRRGGBB` entries. */
@OptIn(UnstableApi::class)
private class ColorTable(private val size: Int, private val argb: IntArray) {

    // Media3 wants [red][green][blue].
    fun toEffect(): SingleColorLut = SingleColorLut.createFromCube(
        Array(size) { r -> Array(size) { g -> IntArray(size) { b -> argb[r + g * size + b * size * size] } } },
    )

    /** Trilinear lookup of straight-alpha ARGB [pixels], keeping alpha. */
    fun applyTo(pixels: IntArray) {
        val n = size - 1
        val plane = size * size
        val shifts = intArrayOf(16, 8, 0)
        val channels = Array(3) { c -> FloatArray(argb.size) { ((argb[it] shr shifts[c]) and 0xFF).toFloat() } }
        val scale = n / 255f
        for (i in pixels.indices) {
            val p = pixels[i]
            val fr = ((p shr 16) and 0xFF) * scale
            val fg = ((p shr 8) and 0xFF) * scale
            val fb = (p and 0xFF) * scale
            val r0 = min(fr.toInt(), n - 1)
            val g0 = min(fg.toInt(), n - 1)
            val b0 = min(fb.toInt(), n - 1)
            val corner = r0 + g0 * size + b0 * plane
            var out = p and -0x1000000
            for (c in 0 until 3) {
                val value = trilinear(channels[c], corner, size, plane, fr - r0, fg - g0, fb - b0)
                out = out or ((value + 0.5f).toInt().coerceIn(0, 255) shl shifts[c])
            }
            pixels[i] = out
        }
    }

    companion object {
        fun parse(map: Map<String, Any?>): ColorTable? {
            val size = (map["lutSize"] as? Number)?.toInt() ?: return null
            val table = when (val raw = map["lut"]) {
                is IntArray -> raw
                is List<*> -> IntArray(raw.size) { (raw[it] as? Number)?.toInt() ?: 0 }
                else -> return null
            }
            return if (size in 2..65 && table.size == size * size * size) ColorTable(size, table) else null
        }
    }
}

/** [table] (red fastest) interpolated between the eight entries from [corner]. */
private fun trilinear(
    table: FloatArray,
    corner: Int,
    size: Int,
    plane: Int,
    dr: Float,
    dg: Float,
    db: Float,
): Float {
    val x00 = table[corner] + (table[corner + 1] - table[corner]) * dr
    val x10 = table[corner + size] + (table[corner + size + 1] - table[corner + size]) * dr
    val x01 = table[corner + plane] + (table[corner + plane + 1] - table[corner + plane]) * dr
    val x11 = table[corner + plane + size] + (table[corner + plane + size + 1] - table[corner + plane + size]) * dr
    val y0 = x00 + (x10 - x00) * dg
    val y1 = x01 + (x11 - x01) * dg
    return y0 + (y1 - y0) * db
}

/**
 * Which layers draw where, in plan order: on the main track (under every video layer), in a
 * compositor slot (video layers; slot 0 is the lowest), or above the composite. A video layer
 * goes to the lowest slot above every slot holding a layer it overlaps in time; an image or colour
 * layer stays on the main track unless it overlaps a slotted or composite layer. A video layer
 * cannot go above an earlier composite layer it overlaps, so such a pair draws in the wrong order.
 */
private class LayerBands(
    val main: List<PlanLayer>,
    val slots: List<List<PlanLayer>>,
    val composition: List<PlanLayer>,
) {
    companion object {
        fun assign(layers: List<PlanLayer>): LayerBands {
            val main = ArrayList<PlanLayer>()
            val slots = ArrayList<ArrayList<PlanLayer>>()
            val composition = ArrayList<PlanLayer>()
            for (layer in layers) {
                if (layer.kind == "video") {
                    val slot = slots.indexOfLast { placed -> placed.any { it.overlaps(layer) } } + 1
                    if (slot == slots.size) slots.add(ArrayList())
                    slots[slot].add(layer)
                } else if (slots.any { placed -> placed.any { it.overlaps(layer) } } ||
                    composition.any { it.overlaps(layer) }
                ) {
                    composition.add(layer)
                } else {
                    main.add(layer)
                }
            }
            return LayerBands(main, slots, composition)
        }
    }
}

/** One [LayerOverlay] per layer, shared by every item that draws it. */
@OptIn(UnstableApi::class)
private class OverlayPool(private val width: Int, private val height: Int) {
    private val overlays = HashMap<PlanLayer, LayerOverlay>()

    /** [layers] bottom to top, at most [OVERLAYS_PER_EFFECT] per [OverlayEffect]. */
    fun effects(layers: List<PlanLayer>): List<Effect> =
        layers.chunked(OVERLAYS_PER_EFFECT).map { chunk ->
            OverlayEffect(chunk.map { layer -> overlays.getOrPut(layer) { LayerOverlay(layer, width, height) } })
        }
}

/**
 * An image or colour layer. Its bitmap is decoded when the layer first becomes active and dropped
 * once it has ended; outside its window it is a transparent pixel at zero alpha. Media3 mixes
 * overlays as straight alpha, so the bitmap is uploaded unpremultiplied. Grain on an image layer is
 * baked into the bitmap once, so its pattern does not change from frame to frame.
 */
@OptIn(UnstableApi::class)
private class LayerOverlay(
    private val layer: PlanLayer,
    private val canvasWidth: Int,
    private val canvasHeight: Int,
) : BitmapOverlay() {
    private var bitmap: Bitmap? = null

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        if (presentationTimeUs < layer.startUs || presentationTimeUs >= layer.endUs) {
            if (presentationTimeUs >= layer.endUs) bitmap = null
            return TRANSPARENT_PIXEL
        }
        bitmap?.let { return it }
        val loaded = try {
            loadLayerBitmap(layer)
        } catch (error: Exception) {
            throw VideoFrameProcessingException(error, presentationTimeUs)
        }
        bitmap = loaded
        return loaded
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        val current = bitmap
        if (current == null || presentationTimeUs < layer.startUs || presentationTimeUs >= layer.endUs) {
            return Placement.HIDDEN
        }
        return Placement.of(
            layer.keyAt(presentationTimeUs),
            current.width,
            current.height,
            canvasWidth,
            canvasHeight,
        )
    }

    companion object {
        private val TRANSPARENT_PIXEL: Bitmap by lazy { Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888) }
    }
}

/**
 * Overlay settings for a layer key: the texture stretched over the rect, rotated about the rect
 * centre and faded. Media3 anchors are NDC with y up, its scale is relative to the texture's own
 * pixels and its rotation is counter-clockwise, hence the negated angle.
 */
@OptIn(UnstableApi::class)
private class Placement(
    private val alpha: Float,
    private val anchor: Pair<Float, Float>,
    private val scale: Pair<Float, Float>,
    private val rotation: Float,
) : OverlaySettings {
    override fun getAlphaScale(): Float = alpha

    override fun getBackgroundFrameAnchor(): Pair<Float, Float> = anchor

    override fun getScale(): Pair<Float, Float> = scale

    override fun getRotationDegrees(): Float = rotation

    companion object {
        val HIDDEN = Placement(0f, Pair.create(0f, 0f), Pair.create(1f, 1f), 0f)

        fun of(
            key: DoubleArray,
            textureWidth: Int,
            textureHeight: Int,
            canvasWidth: Int,
            canvasHeight: Int,
        ): Placement {
            val x = key[1]
            val y = key[2]
            val w = key[3]
            val h = key[4]
            val opacity = key[6].toFloat().coerceIn(0f, 1f)
            // A degenerate rect would make the overlay matrix singular.
            if (w < 0.5 || h < 0.5 || opacity <= 0f) return HIDDEN
            return Placement(
                alpha = opacity,
                anchor = Pair.create(
                    ((x + w / 2) / canvasWidth * 2 - 1).toFloat(),
                    (1 - (y + h / 2) / canvasHeight * 2).toFloat(),
                ),
                scale = Pair.create((w / textureWidth).toFloat(), (h / textureHeight).toFloat()),
                rotation = (-key[5]).toFloat(),
            )
        }
    }
}

/** A video layer's window in its slot sequence and the texture size its frames are scaled to. */
private class SlotEntry(
    val layer: PlanLayer,
    val startUs: Long,
    val endUs: Long,
    val textureWidth: Int,
    val textureHeight: Int,
)

/**
 * Places the compositor inputs. Input 0 is the clock (hidden), inputs 1…n are the slots from top
 * to bottom ([slots] in that order) and the next input is the main track, drawn full frame below
 * them. The compositor draws its primary input on top and the others in reverse input order.
 */
@OptIn(UnstableApi::class)
private class LayerCompositorSettings(
    private val width: Int,
    private val height: Int,
    private val slots: List<List<SlotEntry>>,
) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: List<Size>): Size = Size(width, height)

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        if (inputId == 0) return Placement.HIDDEN
        val slot = slots.getOrNull(inputId - 1) ?: return FULL_FRAME
        val entry = slot.firstOrNull { presentationTimeUs >= it.startUs && presentationTimeUs < it.endUs }
            ?: return Placement.HIDDEN
        return Placement.of(
            entry.layer.keyAt(presentationTimeUs),
            entry.textureWidth,
            entry.textureHeight,
            width,
            height,
        )
    }

    companion object {
        private val FULL_FRAME: OverlaySettings = object : OverlaySettings {}
    }
}

/**
 * Volume with linear fades for one audio segment. It runs after the speed change, so sample
 * positions count timeline time from the segment start.
 */
@OptIn(UnstableApi::class)
private class FadeGain(segment: PlanAudio) : GainProcessor.GainProvider {
    private val volume = segment.volume
    private val fadeIn = segment.fadeIn
    private val fadeOut = segment.fadeOut
    private val duration = segment.sourceDuration / segment.speed

    override fun getGainFactorAtSamplePosition(samplePosition: Long, sampleRate: Int): Float {
        if (unityUntil(samplePosition, sampleRate) != C.TIME_UNSET) return 1f
        val t = samplePosition.toDouble() / sampleRate
        var ramp = 1.0
        if (fadeIn > 0) ramp = min(ramp, t / fadeIn)
        if (fadeOut > 0) ramp = min(ramp, (duration - t) / fadeOut)
        val gain = (volume * ramp.coerceIn(0.0, 1.0)).toFloat()
        return if (gain == 1f) ALMOST_ONE else gain
    }

    override fun isUnityUntil(samplePosition: Long, sampleRate: Int): Long =
        unityUntil(samplePosition, sampleRate)

    /** The end of the unity region holding [samplePosition], or [C.TIME_UNSET] outside one. */
    private fun unityUntil(samplePosition: Long, sampleRate: Int): Long {
        if (volume != 1f) return C.TIME_UNSET
        if (samplePosition < ceil(fadeIn * sampleRate).toLong()) return C.TIME_UNSET
        if (fadeOut <= 0) return C.TIME_END_OF_SOURCE
        val fadeOutStart = floor((duration - fadeOut) * sampleRate).toLong()
        return if (samplePosition < fadeOutStart) fadeOutStart else C.TIME_UNSET
    }
}

/**
 * Scales a frame to the size it has when contained in the canvas, without the letterbox. The
 * matrix is the identity: the output size alone does the scaling.
 */
@OptIn(UnstableApi::class)
private class ContainSize(private val width: Int, private val height: Int) : MatrixTransformation {
    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        val scale = min(width.toFloat() / inputWidth, height.toFloat() / inputHeight)
        return Size(
            (inputWidth * scale).roundToInt().coerceIn(1, width),
            (inputHeight * scale).roundToInt().coerceIn(1, height),
        )
    }

    override fun getMatrix(presentationTimeUs: Long): Matrix = Matrix()
}

/**
 * A clip's key transform in NDC: scale, rotate clockwise about the canvas centre, then translate
 * by (x, y) pixels with y down. [itemStartUs] is the sequence time at which the item shows its
 * local time [localStart].
 */
@OptIn(UnstableApi::class)
private class KeyTransform(
    private val keys: List<DoubleArray>,
    private val width: Int,
    private val height: Int,
    private val itemStartUs: Long,
    private val localStart: Double,
) : MatrixTransformation {
    override fun getMatrix(presentationTimeUs: Long): Matrix {
        val key = evaluateKeys(keys, localStart + (presentationTimeUs - itemStartUs) / 1e6)
        val angle = Math.toRadians(key[4])
        val c = key[1] * cos(angle)
        val s = key[1] * sin(angle)
        val w = width.toDouble()
        val h = height.toDouble()
        return Matrix().apply {
            setValues(
                floatArrayOf(
                    c.toFloat(), (s * h / w).toFloat(), (2 * key[2] / w).toFloat(),
                    (-s * w / h).toFloat(), c.toFloat(), (-2 * key[3] / h).toFloat(),
                    0f, 0f, 1f,
                ),
            )
        }
    }
}

/**
 * Fades an item in from black over [fadeInUs] after [startUs] and out to black over [fadeOutUs]
 * before [endUs] (sequence time), standing in for a crossfade.
 */
@OptIn(UnstableApi::class)
private class DipToBlack(
    private val startUs: Long,
    private val endUs: Long,
    private val fadeInUs: Long,
    private val fadeOutUs: Long,
) : RgbMatrix {
    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        var gain = 1f
        if (fadeInUs > 0) gain = min(gain, (presentationTimeUs - startUs).toFloat() / fadeInUs)
        if (fadeOutUs > 0) gain = min(gain, (endUs - presentationTimeUs).toFloat() / fadeOutUs)
        val g = gain.coerceIn(0f, 1f)
        return floatArrayOf(
            g, 0f, 0f, 0f,
            0f, g, 0f, 0f,
            0f, 0f, g, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}

/**
 * The 4×5 colour matrix as a column-major RgbMatrix; the offsets go in the fourth column, which
 * Media3 multiplies by 1 (alpha is taken as opaque and kept).
 */
@OptIn(UnstableApi::class)
private class ColorMatrixEffect(m: FloatArray) : RgbMatrix {
    private val matrix = floatArrayOf(
        m[0], m[5], m[10], 0f,
        m[1], m[6], m[11], 0f,
        m[2], m[7], m[12], 0f,
        m[3] + m[4], m[8] + m[9], m[13] + m[14], 1f,
    )

    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray = matrix
}

/** Unsharp mask `out = in + amount · (in − blur(in, sigma))`, keeping alpha. */
@OptIn(UnstableApi::class)
private class SharpenEffect(private val amount: Float, private val sigma: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        SharpenProgram(amount, sigma, useHdr)
}

/** Zero-mean monochrome noise with standard deviation [amount], a new pattern every frame. */
@OptIn(UnstableApi::class)
private class GrainEffect(private val amount: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        FrameShaderProgram(GRAIN_SHADER, useHdr) { program, presentationTimeUs ->
            program.setFloatUniform("uAmount", amount)
            program.setFloatUniform("uSeed", ((presentationTimeUs / 1000) % 9973).toFloat())
        }
}

/** Sets alpha to 1, so transparent areas become black before the compositor blends by alpha. */
@OptIn(UnstableApi::class)
private class OpaqueEffect : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        FrameShaderProgram(OPAQUE_SHADER, useHdr) { _, _ -> }
}

/** A full-frame program; the effect's uniforms are set per frame by [setUniforms]. */
@OptIn(UnstableApi::class)
private class FrameShaderProgram(
    fragmentShader: String,
    useHdr: Boolean,
    private val setUniforms: (GlProgram, Long) -> Unit,
) : BaseGlShaderProgram(useHdr, 1) {
    private val program = frameProgram(fragmentShader)

    override fun configure(inputWidth: Int, inputHeight: Int): Size = Size(inputWidth, inputHeight)

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            program.use()
            program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            setUniforms(program, presentationTimeUs)
            program.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (error: GlUtil.GlException) {
            throw VideoFrameProcessingException(error, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            program.delete()
        } catch (error: GlUtil.GlException) {
            throw VideoFrameProcessingException(error)
        }
    }
}

/**
 * Two passes: an alpha-weighted horizontal Gaussian into an intermediate texture, then the
 * vertical Gaussian combined with the input. Transparent pixels (letterbox) do not count, so
 * frame edges get no halo. 13 taps at sigma / 2 cover ±3 sigma.
 */
@OptIn(UnstableApi::class)
private class SharpenProgram(
    private val amount: Float,
    sigma: Float,
    private val useHdr: Boolean,
) : BaseGlShaderProgram(useHdr, 1) {
    private val step = sigma / 2
    private val blurProgram = frameProgram(SHARPEN_BLUR_SHADER)
    private val combineProgram = frameProgram(SHARPEN_COMBINE_SHADER)
    private var width = 0
    private var height = 0
    private var blurTexId = C.INDEX_UNSET
    private var blurFboId = C.INDEX_UNSET

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        if (inputWidth != width || inputHeight != height) {
            try {
                deleteBlurTarget()
                blurTexId = GlUtil.createTexture(inputWidth, inputHeight, useHdr)
                blurFboId = GlUtil.createFboForTexture(blurTexId)
            } catch (error: GlUtil.GlException) {
                throw VideoFrameProcessingException(error)
            }
            width = inputWidth
            height = inputHeight
        }
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            // The caller focused the output texture; draw the blur elsewhere, then come back.
            val output = IntArray(1)
            GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, output, 0)
            GlUtil.focusFramebufferUsingCurrentContext(blurFboId, width, height)
            GlUtil.clearFocusedBuffers()
            blurProgram.use()
            blurProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            blurProgram.setFloatsUniform("uStep", floatArrayOf(step / width, 0f))
            blurProgram.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()

            GlUtil.focusFramebufferUsingCurrentContext(output[0], width, height)
            combineProgram.use()
            combineProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            combineProgram.setSamplerTexIdUniform("uBlurSampler", blurTexId, 1)
            combineProgram.setFloatsUniform("uStep", floatArrayOf(0f, step / height))
            combineProgram.setFloatUniform("uAmount", amount)
            combineProgram.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (error: GlUtil.GlException) {
            throw VideoFrameProcessingException(error, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            blurProgram.delete()
            combineProgram.delete()
            deleteBlurTarget()
        } catch (error: GlUtil.GlException) {
            throw VideoFrameProcessingException(error)
        }
    }

    private fun deleteBlurTarget() {
        if (blurFboId != C.INDEX_UNSET) GlUtil.deleteFbo(blurFboId)
        if (blurTexId != C.INDEX_UNSET) GlUtil.deleteTexture(blurTexId)
        blurFboId = C.INDEX_UNSET
        blurTexId = C.INDEX_UNSET
    }
}

@OptIn(UnstableApi::class)
private fun frameProgram(fragmentShader: String): GlProgram =
    try {
        GlProgram(FRAME_VERTEX_SHADER, fragmentShader).apply {
            setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
        }
    } catch (error: GlUtil.GlException) {
        throw VideoFrameProcessingException(error)
    }

private val FRAME_VERTEX_SHADER = """
    #version 100
    attribute vec4 aFramePosition;
    varying vec2 vTexCoord;
    void main() {
      gl_Position = aFramePosition;
      vTexCoord = aFramePosition.xy * 0.5 + 0.5;
    }
""".trimIndent()

private val SHARPEN_BLUR_SHADER = """
    #version 100
    #ifdef GL_FRAGMENT_PRECISION_HIGH
    precision highp float;
    #else
    precision mediump float;
    #endif
    uniform sampler2D uTexSampler;
    uniform vec2 uStep;
    varying vec2 vTexCoord;
    void main() {
      vec4 sum = vec4(0.0);
      float total = 0.0;
      for (int i = -6; i <= 6; i++) {
        float k = float(i);
        float weight = exp(-k * k / 8.0);
        vec4 color = texture2D(uTexSampler, vTexCoord + uStep * k);
        sum += weight * vec4(color.rgb * color.a, color.a);
        total += weight;
      }
      gl_FragColor = sum / total;
    }
""".trimIndent()

private val SHARPEN_COMBINE_SHADER = """
    #version 100
    #ifdef GL_FRAGMENT_PRECISION_HIGH
    precision highp float;
    #else
    precision mediump float;
    #endif
    uniform sampler2D uTexSampler;
    uniform sampler2D uBlurSampler;
    uniform vec2 uStep;
    uniform float uAmount;
    varying vec2 vTexCoord;
    void main() {
      vec4 sum = vec4(0.0);
      float total = 0.0;
      for (int i = -6; i <= 6; i++) {
        float k = float(i);
        float weight = exp(-k * k / 8.0);
        sum += weight * texture2D(uBlurSampler, vTexCoord + uStep * k);
        total += weight;
      }
      sum /= total;
      vec4 color = texture2D(uTexSampler, vTexCoord);
      vec3 blurred = sum.a > 0.001 ? sum.rgb / sum.a : color.rgb;
      gl_FragColor = vec4(clamp(color.rgb + uAmount * (color.rgb - blurred), 0.0, 1.0), color.a);
    }
""".trimIndent()

// Sum of three hashes: zero mean, standard deviation 0.5 before the factor of 2. Noise is scaled
// by alpha so transparent letterbox areas stay clean.
private val GRAIN_SHADER = """
    #version 100
    #ifdef GL_FRAGMENT_PRECISION_HIGH
    precision highp float;
    #else
    precision mediump float;
    #endif
    uniform sampler2D uTexSampler;
    uniform float uAmount;
    uniform float uSeed;
    varying vec2 vTexCoord;
    float hash(vec3 p3) {
      p3 = fract(p3 * 0.1031);
      p3 += dot(p3, p3.zyx + 31.32);
      return fract((p3.x + p3.y) * p3.z);
    }
    void main() {
      vec4 color = texture2D(uTexSampler, vTexCoord);
      vec2 p = floor(gl_FragCoord.xy);
      float noise = hash(vec3(p, uSeed)) + hash(vec3(p, uSeed + 101.0))
          + hash(vec3(p, uSeed + 211.0)) - 1.5;
      gl_FragColor = vec4(clamp(color.rgb + 2.0 * uAmount * noise * color.a, 0.0, 1.0), color.a);
    }
""".trimIndent()

private val OPAQUE_SHADER = """
    #version 100
    precision mediump float;
    uniform sampler2D uTexSampler;
    varying vec2 vTexCoord;
    void main() {
      gl_FragColor = vec4(texture2D(uTexSampler, vTexCoord).rgb, 1.0);
    }
""".trimIndent()

/**
 * The straight-alpha bitmap of an image or colour layer: decoded near its largest rect size, then
 * its colour table (or matrix), blur, sharpen and a fixed grain pattern applied on the CPU in
 * bitmap pixels.
 */
private fun loadLayerBitmap(layer: PlanLayer): Bitmap {
    val width: Int
    val height: Int
    val pixels: IntArray
    if (layer.kind == "color") {
        width = 1
        height = 1
        pixels = intArrayOf(layer.color)
    } else {
        val file = File(layer.path ?: throw IllegalStateException("A layer has no file."))
        val decoded = decodeLayerImage(file, ceil(layer.maxWidth).toInt(), ceil(layer.maxHeight).toInt())
        width = decoded.width
        height = decoded.height
        pixels = IntArray(width * height)
        decoded.getPixels(pixels, 0, width, 0, 0, width, height)
        decoded.recycle()
    }

    val table = layer.table
    val matrix = layer.filters.colorMatrix
    if (table != null) table.applyTo(pixels) else if (matrix != null) applyColorMatrix(pixels, matrix)
    if (layer.kind != "color" && width * height <= MAX_FILTERED_PIXELS) {
        val toBitmap = (width / max(1.0, layer.maxWidth)).toFloat()
        val filters = layer.filters
        if (filters.blurSigma > MIN_SIGMA) gaussian(pixels, width, height, filters.blurSigma * toBitmap, null)
        if (filters.sharpen > 0f && filters.sharpenSigma > MIN_SIGMA) {
            gaussian(pixels, width, height, filters.sharpenSigma * toBitmap, filters.sharpen)
        }
        if (filters.grain > 0f) addGrain(pixels, filters.grain)
    }

    return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
        setPremultiplied(false)
        setPixels(pixels, 0, width, 0, 0, width, height)
    }
}

/**
 * Adds zero-mean monochrome noise with standard deviation [amount] (0…1 units) to the colour of
 * straight-alpha ARGB [pixels], the same sum-of-three-uniforms noise as [GRAIN_SHADER].
 */
private fun addGrain(pixels: IntArray, amount: Float) {
    val random = Random(GRAIN_SEED)
    val scale = 2f * amount * 255f
    for (i in pixels.indices) {
        val p = pixels[i]
        val noise = (random.nextFloat() + random.nextFloat() + random.nextFloat() - 1.5f) * scale
        val r = (((p shr 16) and 0xFF) + noise + 0.5f).toInt().coerceIn(0, 255)
        val g = (((p shr 8) and 0xFF) + noise + 0.5f).toInt().coerceIn(0, 255)
        val b = ((p and 0xFF) + noise + 0.5f).toInt().coerceIn(0, 255)
        pixels[i] = (p and -0x1000000) or (r shl 16) or (g shl 8) or b
    }
}

private const val GRAIN_SEED = 0x5EED1L

/** CPU filtering is skipped above this size to bound memory. */
private const val MAX_FILTERED_PIXELS = 2048 * 2048

/**
 * Decodes [file] upright, downscaled towards [targetWidth] × [targetHeight] (never below it, never
 * above [MAX_TEXTURE_SIDE]), into a software bitmap.
 */
private fun decodeLayerImage(file: File, targetWidth: Int, targetHeight: Int): Bitmap {
    fun scaleFor(width: Int, height: Int): Float {
        val towardsTarget = max(targetWidth.toFloat() / width, targetHeight.toFloat() / height)
        return min(min(1f, towardsTarget), MAX_TEXTURE_SIDE.toFloat() / max(width, height))
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        return ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            val scale = scaleFor(info.size.width, info.size.height)
            if (scale < 1f) {
                decoder.setTargetSize(
                    max(1, (info.size.width * scale).roundToInt()),
                    max(1, (info.size.height * scale).roundToInt()),
                )
            }
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }

    // Before API 28 BitmapFactory ignores EXIF orientation, so it is applied here.
    val orientation = try {
        ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    } catch (error: Exception) {
        ExifInterface.ORIENTATION_NORMAL
    }
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IllegalStateException("Could not decode ${file.name}.")
    val quarterTurn = orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
        orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
        orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
        orientation == ExifInterface.ORIENTATION_TRANSVERSE
    val uprightWidth = if (quarterTurn) bounds.outHeight else bounds.outWidth
    val uprightHeight = if (quarterTurn) bounds.outWidth else bounds.outHeight
    val scale = scaleFor(uprightWidth, uprightHeight)
    var sample = 1
    while (1f / (sample * 2) >= scale) sample *= 2
    while (max(uprightWidth, uprightHeight) / sample > MAX_TEXTURE_SIDE) sample *= 2
    val raw = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
        ?: throw IllegalStateException("Could not decode ${file.name}.")
    val upright = Matrix()
    when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> upright.setScale(-1f, 1f)
        ExifInterface.ORIENTATION_ROTATE_180 -> upright.setRotate(180f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> upright.setScale(1f, -1f)
        ExifInterface.ORIENTATION_TRANSPOSE -> upright.apply { setRotate(90f); postScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_90 -> upright.setRotate(90f)
        ExifInterface.ORIENTATION_TRANSVERSE -> upright.apply { setRotate(-90f); postScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_270 -> upright.setRotate(270f)
        else -> return raw
    }
    val rotated = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, upright, true)
    if (rotated !== raw) raw.recycle()
    return rotated
}

/** The 4×5 colour matrix on straight-alpha ARGB [pixels]. */
private fun applyColorMatrix(pixels: IntArray, m: FloatArray) {
    fun channel(value: Float): Int = (value * 255f + 0.5f).toInt().coerceIn(0, 255)
    for (i in pixels.indices) {
        val p = pixels[i]
        val a = (p ushr 24) / 255f
        val r = ((p shr 16) and 0xFF) / 255f
        val g = ((p shr 8) and 0xFF) / 255f
        val b = (p and 0xFF) / 255f
        pixels[i] = (channel(m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]) shl 24) or
            (channel(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]) shl 16) or
            (channel(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]) shl 8) or
            channel(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14])
    }
}

/**
 * An alpha-weighted Gaussian of straight-alpha ARGB [pixels] (three box passes per axis). With
 * [sharpen] null the pixels become the blur; otherwise they get the unsharp mask
 * `in + sharpen · (in − blur)` and keep their alpha.
 */
private fun gaussian(pixels: IntArray, width: Int, height: Int, sigma: Float, sharpen: Float?) {
    val radii = boxRadii(sigma)
    if (radii.all { it == 0 }) return
    val n = width * height
    val alpha = FloatArray(n) { (pixels[it] ushr 24).toFloat() }
    val channel = FloatArray(n)
    val scratch = FloatArray(n)
    boxBlur(alpha, scratch, width, height, radii)
    for (shift in intArrayOf(16, 8, 0)) {
        for (i in 0 until n) {
            channel[i] = ((pixels[i] shr shift) and 0xFF) * (pixels[i] ushr 24).toFloat()
        }
        boxBlur(channel, scratch, width, height, radii)
        for (i in 0 until n) {
            val original = (pixels[i] shr shift) and 0xFF
            val blurred = if (alpha[i] > 0.01f) channel[i] / alpha[i] else original.toFloat()
            val value = if (sharpen == null) blurred else original + sharpen * (original - blurred)
            val clamped = (value + 0.5f).toInt().coerceIn(0, 255)
            pixels[i] = (pixels[i] and (0xFF shl shift).inv()) or (clamped shl shift)
        }
    }
    if (sharpen == null) {
        for (i in 0 until n) {
            pixels[i] = (pixels[i] and 0x00FFFFFF) or ((alpha[i] + 0.5f).toInt().coerceIn(0, 255) shl 24)
        }
    }
}

/** Radii of three box blurs approximating a Gaussian of [sigma]. */
private fun boxRadii(sigma: Float): IntArray {
    val ideal = sqrt(12.0 * sigma * sigma / 3 + 1)
    var lower = floor(ideal).toInt()
    if (lower % 2 == 0) lower--
    val upper = lower + 2
    val lowerCount = ((12.0 * sigma * sigma - 3 * lower * lower - 12 * lower - 9) / (-4 * lower - 4)).roundToInt()
    return IntArray(3) { if (it < lowerCount) (lower - 1) / 2 else (upper - 1) / 2 }
}

/** In-place box blurs of [data] with clamped edges; [scratch] holds the horizontal pass. */
private fun boxBlur(data: FloatArray, scratch: FloatArray, width: Int, height: Int, radii: IntArray) {
    for (r in radii) {
        if (r == 0) continue
        val norm = 1f / (2 * r + 1)
        for (y in 0 until height) {
            val row = y * width
            var sum = 0f
            for (k in -r..r) sum += data[row + k.coerceIn(0, width - 1)]
            for (x in 0 until width) {
                scratch[row + x] = sum * norm
                sum += data[row + min(x + r + 1, width - 1)] - data[row + max(x - r, 0)]
            }
        }
        for (x in 0 until width) {
            var sum = 0f
            for (k in -r..r) sum += scratch[k.coerceIn(0, height - 1) * width + x]
            for (y in 0 until height) {
                data[y * width + x] = sum * norm
                sum += scratch[min(y + r + 1, height - 1) * width + x] - scratch[max(y - r, 0) * width + x]
            }
        }
    }
}
