# Android ONNX Inference Setup

GalleryMind now has an Android-first inference layer for the bundled TIDY CLIP
ONNX assets.

## Native Android

- `ClipOnnxBridge.kt` loads:
  - `assets/models/tidy/visual_quant.onnx`
  - `assets/models/tidy/textual_quant.onnx`
  - `assets/models/tidy/vocab.json`
  - `assets/models/tidy/merges.txt`
- `ClipTokenizer.kt` ports the CLIP BPE tokenizer logic used by TIDY.
- `ImagePreprocessor.kt` center-crops images to `224x224` and applies CLIP
  channel normalization.
- `NativeEmbeddingStore.kt` stores embeddings in Android SQLite as float32
  blobs.
- `MainActivity.kt` exposes everything over the `gallerymind/clip`
  MethodChannel.

## Dart API

Use `EmbeddingIndex` from `lib/services/embedding_index.dart`.

```dart
final index = EmbeddingIndex();

await index.indexImage(
  IndexedImageInput(
    id: 'stable-photo-id',
    uri: 'content://or/asset/path',
    imageBytes: bytes,
    title: 'Optional title',
    description: 'Optional description',
    tags: ['tag one', 'tag two'],
  ),
);

final results = await index.searchText('a black dog indoors');
final similar = await index.findSimilarImages('stable-photo-id', threshold: 0.8);
```

Text search uses:

```text
combinedScore = 0.7 * imageEmbeddingScore + 0.3 * captionEmbeddingScore
```

Image-to-image suggestions use image embedding cosine similarity and the
threshold passed to `findSimilarImages`.

## Next Integration Step

The remaining app work is gallery access: fetch image bytes/URIs from the Android
photo library, call `index.indexImage(...)` during first-run indexing, then use
`searchText(...)` and `findSimilarImages(...)` to populate the existing UI.
