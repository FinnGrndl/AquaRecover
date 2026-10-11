package io.github.finngrndl.aquarecover

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.SingleColorLut
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
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/**
 * Renders an AquaRecover timeline on the `aqua_recover/timeline` channel with
 * Media3 Transformer: one sequence of photos and clips, each with its baked
 * colour table, fitted to the output frame. Media3 sequences cannot overlap
 * items, so crossfades render as a short dip through black.
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
        if (transformer != null) {
            result.error("BUSY", "Another timeline export is still running.", null)
            return
        }
        val outputPath = call.argument<String>("outputPath")
        val width = call.argument<Int>("width") ?: 1920
        val height = call.argument<Int>("height") ?: 1080
        val fps = (call.argument<Int>("frameRate") ?: 30).coerceIn(12, 60)
        val clips = call.argument<List<Map<String, Any?>>>("clips")
        if (outputPath.isNullOrBlank() || clips.isNullOrEmpty()) {
            result.error("BAD_ARGS", "outputPath and clips are required", null)
            return
        }
        try {
            val items = clips.mapIndexed { index, clip ->
                val fadeIn = (clip["overlapIn"] as? Number)?.toDouble() ?: 0.0
                val fadeOut = (clips.getOrNull(index + 1)?.get("overlapIn") as? Number)?.toDouble() ?: 0.0
                editedItem(clip, width, height, fps, fadeIn / 2, fadeOut / 2)
            }
            val composition = Composition.Builder(EditedMediaItemSequence.Builder(items).build())
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .experimentalSetForceAudioTrack(true)
                .build()
            File(outputPath).parentFile?.mkdirs()
            File(outputPath).delete()

            pendingResult = result
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
            transformer = null
            pendingResult = null
            result.error("TIMELINE_RENDER_FAILED", error.message, null)
        }
    }

    private fun editedItem(
        clip: Map<String, Any?>,
        width: Int,
        height: Int,
        fps: Int,
        fadeInSeconds: Double,
        fadeOutSeconds: Double,
    ): EditedMediaItem {
        val path = clip["path"] as? String ?: throw IllegalArgumentException("A clip has no file.")
        val isVideo = clip["kind"] == "video"
        val durationUs = (((clip["duration"] as? Number)?.toDouble() ?: 3.0) * 1_000_000).toLong()
        val motion = clip["motion"] as? String ?: "none"
        val size = (clip["lutSize"] as? Number)?.toInt() ?: 0
        val lut = clip["lut"] as? IntArray
        val uri = Uri.fromFile(File(path))

        val effects = ArrayList<Effect>()
        if (lut != null && size in 2..65 && lut.size == size * size * size) {
            // Baked in .cube order (red fastest); Media3 wants [red][green][blue].
            val cube = Array(size) { r ->
                Array(size) { g -> IntArray(size) { b -> lut[r + g * size + b * size * size] } }
            }
            effects.add(SingleColorLut.createFromCube(cube))
        }
        val fills = !isVideo && motion != "none"
        effects.add(
            Presentation.createForWidthAndHeight(
                width,
                height,
                if (fills) Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP else Presentation.LAYOUT_SCALE_TO_FIT,
            ),
        )
        if (fills) effects.add(SlowZoom(durationUs, zoomIn = motion == "zoomIn"))
        if (fadeInSeconds > 0 || fadeOutSeconds > 0) {
            effects.add(DipToBlack(durationUs, (fadeInSeconds * 1e6).toLong(), (fadeOutSeconds * 1e6).toLong()))
        }

        val mediaItem = if (isVideo) {
            val startMs = (((clip["sourceStart"] as? Number)?.toDouble() ?: 0.0) * 1000).toLong()
            MediaItem.Builder()
                .setUri(uri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs)
                        .setEndPositionMs(startMs + durationUs / 1000)
                        .build(),
                )
                .build()
        } else {
            MediaItem.Builder().setUri(uri).setImageDurationMs(durationUs / 1000).build()
        }
        val builder = EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(emptyList(), effects))
            .setRemoveAudio(!isVideo || clip["muted"] == true)
        if (!isVideo) builder.setFrameRate(fps)
        return builder.build()
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

/**
 * Times passed to Media3 effects may be offset by the item's position in the
 * sequence, so both effects below measure from the first frame they see.
 */
@OptIn(UnstableApi::class)
private class SlowZoom(private val durationUs: Long, private val zoomIn: Boolean) : MatrixTransformation {
    private var firstUs = Long.MIN_VALUE

    override fun getMatrix(presentationTimeUs: Long): Matrix {
        if (firstUs == Long.MIN_VALUE) firstUs = presentationTimeUs
        val t = ((presentationTimeUs - firstUs).toFloat() / max(1L, durationUs)).coerceIn(0f, 1f)
        val zoom = if (zoomIn) 1f + 0.15f * t else 1.15f - 0.15f * t
        return Matrix().apply { setScale(zoom, zoom) }
    }
}

@OptIn(UnstableApi::class)
private class DipToBlack(
    private val durationUs: Long,
    private val fadeInUs: Long,
    private val fadeOutUs: Long,
) : RgbMatrix {
    private var firstUs = Long.MIN_VALUE

    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        if (firstUs == Long.MIN_VALUE) firstUs = presentationTimeUs
        val local = presentationTimeUs - firstUs
        var gain = 1f
        if (fadeInUs > 0) gain = min(gain, local.toFloat() / fadeInUs)
        if (fadeOutUs > 0) gain = min(gain, (durationUs - local).toFloat() / fadeOutUs)
        val g = gain.coerceIn(0f, 1f)
        return floatArrayOf(
            g, 0f, 0f, 0f,
            0f, g, 0f, 0f,
            0f, 0f, g, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}
