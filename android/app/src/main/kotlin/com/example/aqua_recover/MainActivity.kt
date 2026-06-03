package com.example.aqua_recover

import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RAW_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeRawToPng", "decodeImageToPng" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "inputPath and outputPath are required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                                throw IllegalStateException("Image decode requires Android 9/API 28 or newer in this bridge.")
                            }
                            decodeWithImageDecoder(inputPath, outputPath)
                            runOnUiThread { result.success(outputPath) }
                        } catch (error: Throwable) {
                            runOnUiThread { result.error("IMAGE_DECODE_FAILED", error.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun decodeWithImageDecoder(inputPath: String, outputPath: String) {
        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.isFile) {
            throw IllegalArgumentException("Input file does not exist.")
        }

        val source = ImageDecoder.createSource(inputFile)
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val width = info.size.width
            val height = info.size.height
            validateDimensions(width, height)
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
        }
        try {
            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { output ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                    throw IllegalStateException("Could not encode decoded image as PNG.")
                }
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun validateDimensions(width: Int, height: Int) {
        if (width <= 0 || height <= 0) {
            throw IllegalArgumentException("Decoded image dimensions are invalid.")
        }
        if (width > MAX_DIMENSION || height > MAX_DIMENSION) {
            throw IllegalArgumentException("Decoded image dimensions exceed the safe limit.")
        }
        if (width.toLong() * height.toLong() > MAX_DECODE_PIXELS) {
            throw IllegalArgumentException("Decoded image is too large for local processing.")
        }
    }

    companion object {
        private const val RAW_CHANNEL = "aqua_recover/raw"
        private const val MAX_DIMENSION = 16384
        private const val MAX_DECODE_PIXELS = 120_000_000L
    }
}
