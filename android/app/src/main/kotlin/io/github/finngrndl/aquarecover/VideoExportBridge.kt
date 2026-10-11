package io.github.finngrndl.aquarecover

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.SingleColorLut
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Android video export on the `aqua_recover/video` channel.
 *
 * Dart samples frames with [sampleFrames], bakes the AquaRecover restoration
 * plus any creative LUT into one 3D colour table, and hands it to
 * [exportWithLut], which renders it on the GPU with Media3 Transformer.
 */
@OptIn(UnstableApi::class)
class VideoExportBridge private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var activeTransformer: Transformer? = null
    private var activeResult: MethodChannel.Result? = null
    private var cancelled = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sampleFrames" -> sampleFrames(call, result)
            "exportWithLut" -> exportWithLut(call, result)
            "cancelRestoreVideo" -> {
                cancelled = true
                activeTransformer?.cancel()
                activeTransformer = null
                activeResult?.error("CANCELLED", "Video export was cancelled.", null)
                activeResult = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun sampleFrames(call: MethodCall, result: MethodChannel.Result) {
        val inputPath = call.argument<String>("inputPath")
        if (inputPath.isNullOrBlank() || !File(inputPath).isFile) {
            result.error("BAD_ARGS", "inputPath must be an existing file", null)
            return
        }
        val count = (call.argument<Int>("count") ?: 5).coerceIn(1, 12)
        val maxDimension = (call.argument<Int>("maxDimension") ?: 384).coerceIn(64, 1024)
        val startSeconds = call.argument<Double>("startSeconds") ?: 0.0
        val endSeconds = call.argument<Double>("endSeconds")
        worker.execute {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(inputPath)
                val durationMs = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                val startUs = (startSeconds * 1_000_000).toLong().coerceAtLeast(0L)
                val endUs = (endSeconds?.let { (it * 1_000_000).toLong() } ?: (durationMs * 1000))
                    .coerceAtMost(durationMs * 1000)
                    .coerceAtLeast(startUs)
                val frames = ArrayList<ByteArray>(count)
                for (i in 0 until count) {
                    // Sample the middle of evenly sized slices, never the very
                    // first frame, which is often a black fade-in.
                    val timeUs = startUs + ((endUs - startUs) * (2 * i + 1)) / (2 * count)
                    val bitmap = frameAt(retriever, timeUs, maxDimension) ?: continue
                    try {
                        val bytes = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, bytes)
                        frames.add(bytes.toByteArray())
                    } finally {
                        bitmap.recycle()
                    }
                }
                mainHandler.post {
                    if (frames.isEmpty()) {
                        result.error("NO_FRAMES", "No video frame could be read.", null)
                    } else {
                        result.success(frames)
                    }
                }
            } catch (error: Throwable) {
                mainHandler.post { result.error("FRAME_SAMPLE_FAILED", error.message, null) }
            } finally {
                retriever.release()
            }
        }
    }

    private fun frameAt(retriever: MediaMetadataRetriever, timeUs: Long, maxDimension: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            return retriever.getScaledFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                maxDimension,
                maxDimension,
            )
        }
        val frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            ?: return null
        val scale = maxDimension.toFloat() / maxOf(frame.width, frame.height)
        if (scale >= 1f) return frame
        val scaled = Bitmap.createScaledBitmap(
            frame,
            (frame.width * scale).toInt().coerceAtLeast(1),
            (frame.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled !== frame) frame.recycle()
        return scaled
    }

    private fun exportWithLut(call: MethodCall, result: MethodChannel.Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val size = call.argument<Int>("lutSize") ?: 0
        val lut = call.argument<IntArray>("lut")
        if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank() || !File(inputPath).isFile) {
            result.error("BAD_ARGS", "inputPath and outputPath are required", null)
            return
        }
        if (size !in 2..65 || lut == null || lut.size != size * size * size) {
            result.error("BAD_ARGS", "lut must hold lutSize³ ARGB values", null)
            return
        }
        if (activeTransformer != null) {
            result.error("BUSY", "Another video export is still running.", null)
            return
        }
        val keepAudio = call.argument<Boolean>("keepAudio") ?: true
        val startSeconds = call.argument<Double>("startSeconds") ?: 0.0
        val endSeconds = call.argument<Double>("endSeconds")

        try {
            val output = File(outputPath)
            output.parentFile?.mkdirs()
            if (output.exists()) output.delete()

            // The baked table arrives in .cube order (red fastest); Media3
            // indexes its cube as [red][green][blue].
            val cube = Array(size) { r ->
                Array(size) { g -> IntArray(size) { b -> lut[r + g * size + b * size * size] } }
            }
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs((startSeconds * 1000).toLong().coerceAtLeast(0L))
            if (endSeconds != null) clipping.setEndPositionMs((endSeconds * 1000).toLong())
            val mediaItem = MediaItem.Builder()
                .setUri(Uri.fromFile(File(inputPath)))
                .setClippingConfiguration(clipping.build())
                .build()
            val edited = EditedMediaItem.Builder(mediaItem)
                .setRemoveAudio(!keepAudio)
                .setEffects(Effects(emptyList(), listOf(SingleColorLut.createFromCube(cube))))
                .build()
            // The colour table is built for SDR; tone-map HDR clips first so
            // HLG/PQ footage is graded in the space the table expects.
            val composition = Composition.Builder(EditedMediaItemSequence.Builder(edited).build())
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()

            cancelled = false
            activeResult = result
            val transformer = Transformer.Builder(context)
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
                        finish { it.error("VIDEO_EXPORT_FAILED", exportException.message, null) }
                    }
                })
                .build()
            activeTransformer = transformer
            transformer.start(composition, outputPath)
        } catch (error: Throwable) {
            activeTransformer = null
            activeResult = null
            result.error("VIDEO_EXPORT_FAILED", error.message, null)
        }
    }

    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        val result = activeResult
        activeTransformer = null
        activeResult = null
        if (result != null && !cancelled) reply(result)
    }

    companion object {
        private const val CHANNEL = "aqua_recover/video"

        fun register(context: Context, messenger: BinaryMessenger) {
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(
                VideoExportBridge(context.applicationContext),
            )
        }
    }
}
