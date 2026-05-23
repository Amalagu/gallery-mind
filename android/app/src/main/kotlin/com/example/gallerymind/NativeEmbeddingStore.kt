package com.example.gallerymind

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import java.nio.ByteBuffer
import java.nio.ByteOrder

// One row in the local vector database. It stores metadata Flutter can display
// plus the actual image/caption embeddings used for ranking.
data class IndexedEmbeddingRecord(
    val id: String,
    val uri: String,
    val title: String,
    val description: String,
    val tags: List<String>,
    val dateTakenMillis: Long,
    val imageEmbedding: FloatArray,
    val captionEmbedding: FloatArray,
)

// Internal ranking object used before the result is converted into a map for
// Flutter's MethodChannel.
data class SearchResultRecord(
    val record: IndexedEmbeddingRecord,
    val imageScore: Double,
    val captionScore: Double,
    val combinedScore: Double,
) {
    fun toMap(): Map<String, Any> {
        return record.toMap() + mapOf(
            "imageScore" to imageScore,
            "captionScore" to captionScore,
            "combinedScore" to combinedScore,
        )
    }
}

fun IndexedEmbeddingRecord.toMap(): Map<String, Any> {
    // Do not send large embedding blobs to Flutter for normal UI work. The UI
    // only needs metadata and URI; native code keeps vectors for search.
    return mapOf(
        "id" to id,
        "uri" to uri,
        "title" to title,
        "description" to description,
        "tags" to tags,
        "dateTakenMillis" to dateTakenMillis,
    )
}

// A small on-device SQLite vector store. For the current app size, brute-force
// scanning embeddings from SQLite is simple and fast enough.
class NativeEmbeddingStore(context: Context) :
    SQLiteOpenHelper(context, DatabaseName, null, DatabaseVersion) {
    override fun onCreate(db: SQLiteDatabase) {
        // Embeddings are stored as little-endian FloatArray blobs to avoid
        // JSON/string overhead for every vector.
        db.execSQL(
            """
            CREATE TABLE image_embeddings (
                id TEXT PRIMARY KEY,
                uri TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                date_taken_millis INTEGER NOT NULL,
                image_embedding BLOB NOT NULL,
                caption_embedding BLOB NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX idx_image_embeddings_updated_at ON image_embeddings(updated_at)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // During early development, schema upgrades rebuild the index. A
        // production app would migrate rows more carefully.
        db.execSQL("DROP TABLE IF EXISTS image_embeddings")
        onCreate(db)
    }

    fun upsert(record: IndexedEmbeddingRecord) {
        // CONFLICT_REPLACE lets re-indexing update an image without duplicate
        // rows.
        val values = ContentValues().apply {
            put("id", record.id)
            put("uri", record.uri)
            put("title", record.title)
            put("description", record.description)
            put("tags_json", JSONArray(record.tags).toString())
            put("date_taken_millis", record.dateTakenMillis)
            put("image_embedding", floatsToBytes(record.imageEmbedding))
            put("caption_embedding", floatsToBytes(record.captionEmbedding))
            put("updated_at", System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict(
            "image_embeddings",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun get(id: String): IndexedEmbeddingRecord? {
        // Used when the detail page asks for images similar to one source image.
        readableDatabase.query(
            "image_embeddings",
            null,
            "id = ?",
            arrayOf(id),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.toRecord() else null
        }
    }

    fun exists(id: String): Boolean {
        // Used by incremental indexing to skip gallery images already embedded.
        readableDatabase.query(
            "image_embeddings",
            arrayOf("id"),
            "id = ?",
            arrayOf(id),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            return cursor.moveToFirst()
        }
    }

    fun getAll(): List<IndexedEmbeddingRecord> {
        // Newest photos appear first on Home, matching the phone gallery feel.
        val records = mutableListOf<IndexedEmbeddingRecord>()
        readableDatabase.query(
            "image_embeddings",
            null,
            null,
            null,
            null,
            null,
            "date_taken_millis DESC, updated_at DESC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                records.add(cursor.toRecord())
            }
        }
        return records
    }

    fun count(): Int {
        readableDatabase.rawQuery("SELECT COUNT(*) FROM image_embeddings", null).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }
    }

    fun clear() {
        writableDatabase.delete("image_embeddings", null, null)
    }

    private fun android.database.Cursor.toRecord(): IndexedEmbeddingRecord {
        // Convert one SQLite cursor row back into the strongly typed native
        // record object used by search and similarity code.
        return IndexedEmbeddingRecord(
            id = getString(getColumnIndexOrThrow("id")),
            uri = getString(getColumnIndexOrThrow("uri")),
            title = getString(getColumnIndexOrThrow("title")),
            description = getString(getColumnIndexOrThrow("description")),
            tags = jsonArrayToStrings(getString(getColumnIndexOrThrow("tags_json"))),
            dateTakenMillis = getLong(getColumnIndexOrThrow("date_taken_millis")),
            imageEmbedding = bytesToFloats(getBlob(getColumnIndexOrThrow("image_embedding"))),
            captionEmbedding = bytesToFloats(getBlob(getColumnIndexOrThrow("caption_embedding"))),
        )
    }

    private fun jsonArrayToStrings(json: String): List<String> {
        val array = JSONArray(json)
        return List(array.length()) { index -> array.getString(index) }
    }

    private fun floatsToBytes(values: FloatArray): ByteArray {
        // SQLite has no FloatArray column type, so each float is packed into four
        // bytes using a fixed byte order.
        val buffer = ByteBuffer.allocate(values.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        values.forEach { buffer.putFloat(it) }
        return buffer.array()
    }

    private fun bytesToFloats(bytes: ByteArray): FloatArray {
        // Reverse of floatsToBytes when loading vectors for search.
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return FloatArray(bytes.size / 4) { buffer.getFloat() }
    }

    private companion object {
        private const val DatabaseName = "gallerymind_embeddings.db"
        private const val DatabaseVersion = 3
    }
}
