package com.example.gallerymind

import android.graphics.Bitmap
import java.nio.FloatBuffer

// Converts Android Bitmaps into the exact tensor layout expected by the CLIP
// image encoder.
object ImagePreprocessor {
    fun preprocess(bitmap: Bitmap): FloatBuffer {
        // ONNX expects CHW order: all red pixels first, then green, then blue.
        // Each channel is normalized with CLIP's training mean/std values.
        val imageSize = bitmap.width
        val stride = imageSize * imageSize
        val imageData = FloatBuffer.allocate(3 * stride)
        val pixels = IntArray(stride)

        bitmap.getPixels(pixels, 0, imageSize, 0, 0, imageSize, imageSize)
        for (row in 0 until imageSize) {
            for (column in 0 until imageSize) {
                val index = imageSize * row + column
                val pixel = pixels[index]
                imageData.put(index, (((pixel shr 16 and 0xFF) / 255f - 0.48145467f) / 0.26862955f))
                imageData.put(
                    index + stride,
                    (((pixel shr 8 and 0xFF) / 255f - 0.4578275f) / 0.2613026f),
                )
                imageData.put(
                    index + stride * 2,
                    (((pixel and 0xFF) / 255f - 0.40821072f) / 0.2757771f),
                )
            }
        }

        imageData.rewind()
        return imageData
    }

    fun centerCrop(bitmap: Bitmap, imageSize: Int): Bitmap {
        // CLIP was trained on square image crops, so use the centered square
        // region and resize it to 224x224 before preprocessing.
        val cropSize = minOf(bitmap.width, bitmap.height)
        val cropX = (bitmap.width - cropSize) / 2
        val cropY = (bitmap.height - cropSize) / 2
        val cropped = Bitmap.createBitmap(bitmap, cropX, cropY, cropSize, cropSize)
        return Bitmap.createScaledBitmap(cropped, imageSize, imageSize, false)
    }
}
