package com.example.gallerymind

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.IntBuffer
import java.util.Collections
import java.io.ByteArrayOutputStream
import kotlin.math.sqrt

// ClipOnnxBridge owns the native ML pipeline: load ONNX sessions, preprocess
// images/text, store embeddings, and answer search/similarity requests.
class ClipOnnxBridge(private val context: Context) {
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val embeddingStore = NativeEmbeddingStore(context)
    private var textSession: OrtSession? = null
    private var imageSession: OrtSession? = null
    private var tokenizer: ClipTokenizer? = null

    @Synchronized
    fun initialize() {
        // Search needs both model halves, while gallery indexing can load only
        // the visual half. Keep this as the full initialization path for calls
        // that genuinely need text and image embeddings.
        initializeImageModel()
        initializeTextModel()
    }

    fun initializeTextSearch() {
        // Flutter calls this shortly after Home opens so the first user search
        // does not have to wait for tokenizer/model startup.
        initializeTextModel()
    }

    @Synchronized
    private fun initializeTextModel() {
        // The text model is lazy-loaded. This keeps first-launch indexing from
        // waiting on an ONNX session it does not need yet.
        if (textSession != null && tokenizer != null) return
        Log.i(LogTag, "Loading CLIP text model")
        textSession = env.createSession(readFlutterAsset("assets/models/tidy/textual_quant.onnx"))
        tokenizer = ClipTokenizer(loadVocab(), loadMerges())
        Log.i(LogTag, "CLIP text model loaded")
    }

    @Synchronized
    private fun initializeImageModel() {
        // Gallery indexing only needs this visual model. Loading it separately
        // makes the onboarding pass begin much sooner on real devices.
        if (imageSession != null) return
        Log.i(LogTag, "Loading CLIP visual model")
        imageSession = env.createSession(readFlutterAsset("assets/models/tidy/visual_quant.onnx"))
        Log.i(LogTag, "CLIP visual model loaded")
    }

    fun embedText(text: String): FloatArray {
        initializeTextModel()
        // CLIP text input is always exactly 77 tokens with start/end tokens and
        // an attention mask that tells the model which positions are real text.
        val tokenIds = tokenizeForClip(text)
        val endTokenIndex = tokenIds.indexOf(TokenEndOfText).let { index ->
            if (index >= 0) index else 0
        }
        val attentionMask = IntArray(ClipTextLength) { index ->
            if (index <= endTokenIndex) 1 else 0
        }

        val shape = longArrayOf(1, ClipTextLength.toLong())
        val inputIdsTensor = OnnxTensor.createTensor(env, IntBuffer.wrap(tokenIds), shape)
        val attentionMaskTensor = OnnxTensor.createTensor(env, IntBuffer.wrap(attentionMask), shape)

        inputIdsTensor.use { inputIds ->
            attentionMaskTensor.use { mask ->
                val inputs = hashMapOf(
                    "input_ids" to inputIds,
                    "attention_mask" to mask,
                )
                textSession!!.run(inputs).use { output ->
                    // Normalizing here means later cosine comparisons are stable
                    // and do not depend on raw vector magnitude.
                    return normalizeL2(extractEmbedding(output[0].value))
                }
            }
        }
    }

    fun embedImageAsset(assetPath: String): FloatArray {
        initializeImageModel()
        val bytes = readFlutterAsset(assetPath)
        return embedImageBytes(bytes)
    }

    fun embedImageBytes(bytes: ByteArray): FloatArray {
        initializeImageModel()
        // Decode arbitrary image bytes into a Bitmap before CLIP preprocessing.
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("Unable to decode image bytes")
        return embedBitmap(bitmap)
    }

    fun embedImageUri(uri: Uri): FloatArray {
        initializeImageModel()
        // MediaStore images can be huge. Decode a sampled bitmap first to avoid
        // out-of-memory crashes on real devices.
        return embedBitmap(decodeSampledBitmap(uri, 768))
    }

    fun indexImageAsset(
        id: String,
        uri: String,
        assetPath: String,
        title: String,
        description: String,
        tags: List<String>,
        dateTakenMillis: Long = System.currentTimeMillis(),
    ): Map<String, Any> {
        val imageEmbedding = embedImageAsset(assetPath)
        return indexPrecomputedImage(
            id,
            uri,
            title,
            description,
            tags,
            dateTakenMillis,
            imageEmbedding,
        )
    }

    fun indexImageBytes(
        id: String,
        uri: String,
        bytes: ByteArray,
        title: String,
        description: String,
        tags: List<String>,
        dateTakenMillis: Long = System.currentTimeMillis(),
    ): Map<String, Any> {
        val imageEmbedding = embedImageBytes(bytes)
        return indexPrecomputedImage(
            id,
            uri,
            title,
            description,
            tags,
            dateTakenMillis,
            imageEmbedding,
        )
    }

    fun indexImageUri(
        id: String,
        uri: Uri,
        title: String,
        description: String,
        tags: List<String>,
        dateTakenMillis: Long,
    ): Map<String, Any> {
        val imageEmbedding = embedImageUri(uri)
        return indexPrecomputedImage(
            id,
            uri.toString(),
            title,
            description,
            tags,
            dateTakenMillis,
            imageEmbedding,
        )
    }

    fun searchText(
        query: String,
        limit: Int,
        imageWeight: Double,
        captionWeight: Double,
        threshold: Double,
    ): List<Map<String, Any>> {
        val startMillis = System.currentTimeMillis()
        Log.i(LogTag, "Text search started: query='$query', limit=$limit, threshold=$threshold")
        val queryEmbedding = embedText(query)
        val records = embeddingStore.getAll()
        val ranked = records
            .map { record ->
                // Query text is compared to the actual image embedding and,
                // when available, to the caption/title/tag text embedding.
                val imageScore = normalizedSimilarity(queryEmbedding, record.imageEmbedding)
                val captionScore = normalizedSimilarity(queryEmbedding, record.captionEmbedding)
                val hasCaptionSignal = hasEmbeddingSignal(record.captionEmbedding)
                SearchResultRecord(
                    record = record,
                    imageScore = imageScore,
                    captionScore = captionScore,
                    combinedScore = if (hasCaptionSignal) {
                        imageWeight * imageScore + captionWeight * captionScore
                    } else {
                        // If there is no caption/tag embedding, do not waste
                        // 30% of the score. The image score gets full weight.
                        imageScore
                    },
                )
            }
            .sortedByDescending { it.combinedScore }
        val filtered = ranked.filter { it.combinedScore >= threshold }
        val selected = if (filtered.isNotEmpty()) {
            filtered
        } else {
            // If the on-device text side gives slightly lower scores than the
            // desktop export sanity check, avoid showing a dead search screen.
            // The original score is still returned so the UI can display true
            // confidence values.
            ranked.take(minOf(limit, SearchFallbackLimit))
        }
        val results = selected
            .take(limit)
            .map { it.toMap() }
        Log.i(
            LogTag,
            "Text search finished: query='$query', records=${records.size}, filtered=${filtered.size}, results=${results.size}, topScore=${ranked.firstOrNull()?.combinedScore ?: 0.0}, elapsedMs=${System.currentTimeMillis() - startMillis}",
        )
        return results
    }

    fun findSimilarImages(
        sourceImageId: String,
        threshold: Double,
        limit: Int,
    ): List<Map<String, Any>> {
        // Image-detail suggestions are pure visual similarity, not text search.
        val source = embeddingStore.get(sourceImageId) ?: return emptyList()
        return embeddingStore.getAll()
            .asSequence()
            .filter { it.id != sourceImageId }
            .map { record ->
                val score = normalizedSimilarity(source.imageEmbedding, record.imageEmbedding)
                SearchResultRecord(
                    record = record,
                    imageScore = score,
                    captionScore = 0.0,
                    combinedScore = score,
                )
            }
            .filter { it.combinedScore >= threshold }
            .sortedByDescending { it.combinedScore }
            .take(limit)
            .map { it.toMap() }
            .toList()
    }

    fun getAllIndexedImages(limit: Int): List<Map<String, Any>> {
        // Used by the Home page to render the date-grouped gallery.
        return embeddingStore.getAll()
            .take(limit)
            .map { it.toMap() }
    }

    fun getImageBytes(uri: String, maxSize: Int): ByteArray {
        // Flutter requests thumbnail/display bytes for content:// images through
        // this method because Dart cannot read Android gallery URIs directly.
        if (uri.startsWith("assets/")) return readFlutterAsset(uri)
        val bitmap = decodeSampledBitmap(Uri.parse(uri), maxSize)
        val resized = resizeToMax(bitmap, maxSize)
        val output = ByteArrayOutputStream()
        resized.compress(Bitmap.CompressFormat.JPEG, 88, output)
        return output.toByteArray()
    }

    fun countIndexedImages(): Int = embeddingStore.count()

    fun clearIndex() {
        embeddingStore.clear()
    }

    fun indexNewGalleryImages(
        includeAlreadyIndexed: Boolean = false,
        limit: Int? = null,
        onProgress: (Map<String, Any>) -> Unit,
    ): Map<String, Any> {
        // Query Android MediaStore for every gallery image, then skip anything
        // already present in the local SQLite index.
        val candidates = getGalleryCandidates()
        var skipped = 0
        val pending = candidates.filter { candidate ->
            val alreadyIndexed = embeddingStore.exists(candidate.indexId)
            if (alreadyIndexed && !includeAlreadyIndexed) {
                skipped += 1
                false
            } else {
                true
            }
        }.let { filtered ->
            if (limit != null) filtered.take(limit) else filtered
        }

        Log.i(
            LogTag,
            "Indexing gallery images: total=${candidates.size}, pending=${pending.size}, skipped=$skipped, limit=$limit",
        )
        onProgress(
            mapOf(
                "completed" to 0,
                "total" to pending.size,
                "indexed" to 0,
                "skipped" to skipped,
                "failed" to 0,
                "currentId" to "",
            ),
        )

        var indexed = 0
        var failed = 0
        pending.forEachIndexed { index, candidate ->
            try {
                // Device gallery filenames stay available for literal filename
                // search, but are not embedded as caption text.
                indexImageUri(
                    id = candidate.indexId,
                    uri = candidate.uri,
                    title = candidate.title,
                    description = "",
                    tags = emptyList(),
                    dateTakenMillis = candidate.dateTakenMillis,
                )
                indexed += 1
            } catch (error: Throwable) {
                failed += 1
                Log.w(LogTag, "Failed to index ${candidate.indexId}: ${error.message}", error)
            }

            onProgress(
                // Dart uses these numbers to update the circular progress UI.
                mapOf(
                    "completed" to index + 1,
                    "total" to pending.size,
                    "indexed" to indexed,
                    "skipped" to skipped,
                    "failed" to failed,
                    "currentId" to candidate.indexId,
                ),
            )
        }

        return mapOf(
            "totalGalleryImages" to candidates.size,
            "processed" to pending.size,
            "indexed" to indexed,
            "skipped" to skipped,
            "failed" to failed,
            "stored" to embeddingStore.count(),
        )
    }

    @Synchronized
    fun close() {
        textSession?.close()
        imageSession?.close()
        textSession = null
        imageSession = null
        tokenizer = null
    }

    private fun tokenizeForClip(text: String): IntArray {
        // Tidy/OpenCLIP expects lowercase alphanumeric-ish text plus CLIP's
        // special start/end tokens, padded or trimmed to ClipTextLength.
        val cleaned = TextCleanupRegex.replace(text, "").lowercase()
        val tokens = mutableListOf<Int>()
        tokens.add(TokenStartOfText)
        tokens.addAll(tokenizer!!.encode(cleaned))
        tokens.add(TokenEndOfText)

        val activeTokenCount = minOf(tokens.size, ClipTextLength)
        return IntArray(ClipTextLength) { index ->
            if (index < tokens.size) tokens[index] else 0
        }.also {
            if (activeTokenCount == ClipTextLength) {
                it[ClipTextLength - 1] = TokenEndOfText
            }
        }
    }

    private fun indexPrecomputedImage(
        id: String,
        uri: String,
        title: String,
        description: String,
        tags: List<String>,
        dateTakenMillis: Long,
        imageEmbedding: FloatArray,
    ): Map<String, Any> {
        // Store a visual embedding for the image and a second optional embedding
        // for real descriptive text. The filename/title is kept for display and
        // literal filename search, but it should not consume the 0.3 caption
        // weight in semantic ranking.
        val captionText = listOf(description, tags.joinToString(" "))
            .filter { it.isNotBlank() }
            .joinToString(" ")
        val captionEmbedding = if (captionText.isBlank()) {
            FloatArray(imageEmbedding.size)
        } else {
            embedText(captionText)
        }
        val record = IndexedEmbeddingRecord(
            id = id,
            uri = uri,
            title = title,
            description = description,
            tags = tags,
            dateTakenMillis = dateTakenMillis,
            imageEmbedding = imageEmbedding,
            captionEmbedding = captionEmbedding,
        )
        embeddingStore.upsert(record)
        return record.toMap()
    }

    private fun loadVocab(): Map<String, Int> {
        // vocab.json maps BPE token strings to the integer IDs the text model
        // was trained with.
        val json = JSONObject(readFlutterAsset("assets/models/tidy/vocab.json").decodeToString())
        val vocab = HashMap<String, Int>(json.length())
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            vocab[key.replace("</w>", " ")] = json.getInt(key)
        }
        return vocab
    }

    private fun getGalleryCandidates(): List<GalleryCandidate> {
        // MediaStore is Android's indexed database of photos/videos. We read IDs,
        // display names, and dates without loading image pixels yet.
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_MODIFIED,
        )
        val candidates = mutableListOf<GalleryCandidate>()
        context.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_TAKEN} DESC, ${MediaStore.Images.Media.DATE_MODIFIED} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val dateTakenColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            while (cursor.moveToNext()) {
                val mediaId = cursor.getLong(idColumn)
                val displayName = cursor.getString(nameColumn).orEmpty()
                val dateTaken = cursor.getLong(dateTakenColumn)
                val modified = cursor.getLong(modifiedColumn) * 1000L
                val uri = ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    mediaId,
                )
                candidates.add(
                    GalleryCandidate(
                        // Prefixing with media: keeps device gallery IDs distinct
                        // from any future asset/demo IDs.
                        indexId = "media:$mediaId",
                        uri = uri,
                        title = displayName.substringBeforeLast('.', displayName),
                        dateTakenMillis = if (dateTaken > 0) dateTaken else modified,
                    ),
                )
            }
        }
        return candidates
    }

    private fun loadMerges(): Map<Pair<String, String>, Int> {
        // merges.txt gives the byte-pair merge priority table used by CLIP's
        // tokenizer.
        val merges = HashMap<Pair<String, String>, Int>()
        BufferedReader(
            InputStreamReader(
                context.assets.open("flutter_assets/assets/models/tidy/merges.txt"),
            ),
        ).useLines { lines ->
            lines.drop(1).forEachIndexed { index, line ->
                val parts = line.split(" ")
                if (parts.size >= 2) {
                    merges[parts[0] to parts[1].replace("</w>", " ")] = index
                }
            }
        }
        return merges
    }

    private fun embedBitmap(bitmap: Bitmap): FloatArray {
        // CLIP visual models expect a centered 224x224 tensor in CHW format.
        val cropped = ImagePreprocessor.centerCrop(bitmap, ClipImageSize)
        val inputTensor = OnnxTensor.createTensor(
            env,
            ImagePreprocessor.preprocess(cropped),
            longArrayOf(1, 3, ClipImageSize.toLong(), ClipImageSize.toLong()),
        )

        inputTensor.use { tensor ->
            imageSession!!.run(Collections.singletonMap("pixel_values", tensor)).use { output ->
                return normalizeL2(extractEmbedding(output[0].value))
            }
        }
    }

    private fun decodeSampledBitmap(uri: Uri, requestedMaxSize: Int): Bitmap {
        // First decode only bounds, then choose an inSampleSize, then decode the
        // actual pixels. This avoids loading a 12MP photo just for inference.
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        }
        val sampleSize = calculateInSampleSize(bounds, requestedMaxSize)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        } ?: throw IllegalArgumentException("Unable to decode image: $uri")
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, requestedMaxSize: Int): Int {
        // Use power-of-two downsampling because BitmapFactory handles it
        // efficiently on Android.
        val height = options.outHeight
        val width = options.outWidth
        var sampleSize = 1
        if (height > requestedMaxSize || width > requestedMaxSize) {
            var halfHeight = height / 2
            var halfWidth = width / 2
            while (halfHeight / sampleSize >= requestedMaxSize &&
                halfWidth / sampleSize >= requestedMaxSize
            ) {
                sampleSize *= 2
            }
        }
        return sampleSize.coerceAtLeast(1)
    }

    private fun readFlutterAsset(path: String): ByteArray {
        // Android sees Flutter assets under the flutter_assets/ prefix inside
        // the APK.
        val normalized = path.removePrefix("flutter_assets/")
        return context.assets.open("flutter_assets/$normalized").use { it.readBytes() }
    }

    private fun extractEmbedding(value: Any): FloatArray {
        // ONNX Runtime may return either a FloatArray or a batch array holding
        // the first FloatArray depending on model output shape.
        @Suppress("UNCHECKED_CAST")
        return when (value) {
            is Array<*> -> (value[0] as FloatArray)
            is FloatArray -> value
            else -> throw IllegalStateException("Unexpected ONNX output type: ${value.javaClass.name}")
        }
    }

    private fun normalizeL2(input: FloatArray): FloatArray {
        // Convert an embedding to unit length so dot product and cosine
        // similarity behave consistently.
        var norm = 0.0f
        for (value in input) {
            norm += value * value
        }
        val length = sqrt(norm)
        if (length == 0.0f) return input
        return FloatArray(input.size) { index -> input[index] / length }
    }

    private fun cosineSimilarity(left: FloatArray, right: FloatArray): Double {
        // Cosine similarity measures angle between vectors. Higher means more
        // semantically/visually similar.
        val length = minOf(left.size, right.size)
        if (length == 0) return 0.0
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for (index in 0 until length) {
            dot += left[index] * right[index]
            leftNorm += left[index] * left[index]
            rightNorm += right[index] * right[index]
        }
        if (leftNorm == 0.0 || rightNorm == 0.0) return 0.0
        return dot / (sqrt(leftNorm.toFloat()) * sqrt(rightNorm.toFloat()))
    }

    private fun normalizedSimilarity(left: FloatArray, right: FloatArray): Double {
        // Raw cosine is -1..1. The UI thresholds are easier to reason about as
        // percentages, so map it into 0..1.
        val cosine = cosineSimilarity(left, right)
        return ((cosine + 1.0) / 2.0).coerceIn(0.0, 1.0)
    }

    private fun hasEmbeddingSignal(values: FloatArray): Boolean {
        // A blank caption is stored as all zeroes; any non-trivial value means
        // description/tag text should contribute to search ranking.
        return values.any { kotlin.math.abs(it) > 0.000001f }
    }

    private fun resizeToMax(bitmap: Bitmap, maxSize: Int): Bitmap {
        // Used for display bytes sent to Flutter, not for model inference.
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= maxSize) return bitmap
        val scale = maxSize.toFloat() / longest.toFloat()
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    private data class GalleryCandidate(
        val indexId: String,
        val uri: android.net.Uri,
        val title: String,
        val dateTakenMillis: Long,
    )

    private companion object {
        private const val ClipImageSize = 224
        private const val ClipTextLength = 77
        private const val TokenStartOfText = 49406
        private const val TokenEndOfText = 49407
        private const val SearchFallbackLimit = 60
        private const val LogTag = "GalleryMindClip"
        private val TextCleanupRegex = Regex("[^A-Za-z0-9 ]")
    }
}
