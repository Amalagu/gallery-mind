import '../data/sample_gallery.dart';
import 'embedding_index.dart';

// Helper used by tests/smoke flows to index the bundled sample images through
// the same native path used for real gallery photos.
class SampleIndexSeeder {
  const SampleIndexSeeder(this.index);

  final EmbeddingIndex index;

  Future<void> indexBundledSamples({
    void Function(int completed, int total)? onProgress,
  }) async {
    // Each sample image becomes an IndexedImageInput, which the native layer
    // turns into CLIP embeddings and stores in SQLite.
    await index.indexImages(
      sampleGalleryImages.map(
        (image) => IndexedImageInput(
          id: image.id,
          uri: image.assetPath,
          assetPath: image.assetPath,
          title: image.title,
          description: image.description,
          tags: image.tags,
        ),
      ),
      onProgress: onProgress,
    );
  }
}
