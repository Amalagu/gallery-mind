import 'package:flutter/services.dart';

// Data passed from Flutter into native Android when we want an image indexed.
// It can describe either a bundled asset image or raw image bytes.
class IndexedImageInput {
  const IndexedImageInput({
    required this.id,
    required this.uri,
    this.assetPath,
    this.imageBytes,
    this.title = '',
    this.description = '',
    this.tags = const [],
    this.dateTakenMillis,
  }) : assert(assetPath != null || imageBytes != null);

  final String id;
  final String uri;
  final String? assetPath;
  final Uint8List? imageBytes;
  final String title;
  final String description;
  final List<String> tags;
  final int? dateTakenMillis;
}

// Data returned from native Android after an image has been indexed/stored.
// This intentionally excludes the embedding vectors; vectors stay native-side
// in SQLite so Flutter does not move large arrays around unnecessarily.
class IndexedImageRecord {
  const IndexedImageRecord({
    required this.id,
    required this.uri,
    required this.title,
    required this.description,
    required this.tags,
    required this.dateTakenMillis,
  });

  final String id;
  final String uri;
  final String title;
  final String description;
  final List<String> tags;
  final int dateTakenMillis;

  factory IndexedImageRecord.fromMap(Map<Object?, Object?> map) {
    return IndexedImageRecord(
      id: map['id']! as String,
      uri: map['uri']! as String,
      title: map['title']! as String,
      description: map['description']! as String,
      tags: (map['tags']! as List).cast<String>().toList(growable: false),
      dateTakenMillis: (map['dateTakenMillis'] as num?)?.toInt() ?? 0,
    );
  }
}

// Result row returned by semantic search. It includes both the image metadata
// and the similarity scores used to rank/display the match.
class SemanticSearchResult {
  const SemanticSearchResult({
    required this.record,
    required this.imageScore,
    required this.captionScore,
    required this.combinedScore,
  });

  final IndexedImageRecord record;
  final double imageScore;
  final double captionScore;
  final double combinedScore;

  factory SemanticSearchResult.fromMap(Map<Object?, Object?> map) {
    return SemanticSearchResult(
      record: IndexedImageRecord.fromMap(map),
      imageScore: (map['imageScore']! as num).toDouble(),
      captionScore: (map['captionScore']! as num).toDouble(),
      combinedScore: (map['combinedScore']! as num).toDouble(),
    );
  }
}

// EmbeddingIndex is Flutter's high-level API for all native AI/index actions.
// Internally it talks to MainActivity.kt over a MethodChannel named
// "gallerymind/clip".
class EmbeddingIndex {
  EmbeddingIndex({
    MethodChannel? channel,
    double imageWeight = 0.7,
    double captionWeight = 0.3,
  })  : _channel = channel ?? const MethodChannel('gallerymind/clip'),
        _imageWeight = imageWeight,
        _captionWeight = captionWeight;

  final MethodChannel _channel;
  final double _imageWeight;
  final double _captionWeight;
  bool _initialized = false;
  void Function(IndexProgress progress)? onIndexProgress;

  Future<void> initialize() async {
    // The native side lazily loads ONNX models. Calling initialize once avoids
    // reloading heavy model sessions for every search/index call.
    if (_initialized) return;
    await _channel.invokeMethod<bool>('initialize');
    _initialized = true;
  }

  Future<IndexedImageRecord> indexImage(IndexedImageInput input) async {
    await initialize();
    // Asset images and byte images use different native methods, but both end
    // up in the same SQLite embedding store.
    final method =
        input.assetPath != null ? 'indexImageAsset' : 'indexImageBytes';
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      method,
      {
        'id': input.id,
        'uri': input.uri,
        'assetPath': input.assetPath,
        'bytes': input.imageBytes,
        'title': input.title,
        'description': input.description,
        'tags': input.tags,
        'dateTakenMillis': input.dateTakenMillis,
      },
    );
    return IndexedImageRecord.fromMap(result!);
  }

  Future<List<IndexedImageRecord>> indexImages(
    Iterable<IndexedImageInput> inputs, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final list = inputs.toList(growable: false);
    final records = <IndexedImageRecord>[];
    for (var index = 0; index < list.length; index += 1) {
      records.add(await indexImage(list[index]));
      onProgress?.call(index + 1, list.length);
    }
    return records;
  }

  Future<List<SemanticSearchResult>> searchText(
    String query, {
    int limit = 30,
    double threshold = 0.5,
  }) async {
    await initialize();
    // Native Android embeds the query text, compares it against stored image
    // embeddings, applies the threshold, and returns ranked rows.
    final rows = await _channel.invokeMethod<List<Object?>>(
      'searchText',
      {
        'query': query,
        'limit': limit,
        'imageWeight': _imageWeight,
        'captionWeight': _captionWeight,
        'threshold': threshold,
      },
    );
    return _resultsFromRows(rows);
  }

  Future<List<SemanticSearchResult>> findSimilarImages(
    String sourceImageId, {
    double threshold = 0.8,
    int limit = 60,
  }) async {
    await initialize();
    // This is image-to-image search. It compares one stored image embedding
    // against all other stored image embeddings.
    final rows = await _channel.invokeMethod<List<Object?>>(
      'findSimilarImages',
      {
        'sourceImageId': sourceImageId,
        'threshold': threshold,
        'limit': limit,
      },
    );
    return _resultsFromRows(rows);
  }

  Future<List<IndexedImageRecord>> getAllIndexedImages(
      {int limit = 5000}) async {
    await initialize();
    // Used by Home and filename search to list images already present in the
    // native embedding database.
    final rows = await _channel.invokeMethod<List<Object?>>(
      'getAllIndexedImages',
      {'limit': limit},
    );
    return (rows ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(IndexedImageRecord.fromMap)
        .toList(growable: false);
  }

  Future<Uint8List> getImageBytes(String uri, {int maxSize = 640}) async {
    // Flutter cannot directly render Android content:// images, so native code
    // reads and downscales the image, then returns JPEG bytes for Image.memory.
    final bytes = await _channel.invokeMethod<Uint8List>(
      'getImageBytes',
      {
        'uri': uri,
        'maxSize': maxSize,
      },
    );
    return bytes!;
  }

  Future<void> shareImage(String uri) async {
    // Delegates to Android's ACTION_SEND share sheet for gallery images.
    await _channel.invokeMethod<bool>(
      'shareImage',
      {'uri': uri},
    );
  }

  Future<bool> hasPhotoPermission() async {
    final granted = await _channel.invokeMethod<bool>('hasPhotoPermission');
    return granted ?? false;
  }

  Future<bool> requestPhotoPermission() async {
    final granted = await _channel.invokeMethod<bool>('requestPhotoPermission');
    return granted ?? false;
  }

  Future<bool> hasCompletedOnboarding() async {
    final completed =
        await _channel.invokeMethod<bool>('hasCompletedOnboarding');
    return completed ?? false;
  }

  Future<void> completeOnboarding() async {
    await _channel.invokeMethod<bool>('completeOnboarding');
  }

  Future<GalleryIndexSummary> indexNewGalleryImages({
    bool includeAlreadyIndexed = false,
    int? limit,
    void Function(IndexProgress progress)? onProgress,
  }) async {
    await initialize();
    // Native indexing can take a while. We register a callback so Android can
    // push progress events back to Flutter while it works.
    onIndexProgress = onProgress;
    _channel.setMethodCallHandler(_handleNativeCallback);
    final summary = await _channel.invokeMethod<Map<Object?, Object?>>(
      'indexNewGalleryImages',
      {
        'includeAlreadyIndexed': includeAlreadyIndexed,
        'limit': limit,
      },
    );
    return GalleryIndexSummary.fromMap(summary!);
  }

  Future<int> count() async {
    await initialize();
    final count = await _channel.invokeMethod<int>('countIndexedImages');
    return count ?? 0;
  }

  Future<void> clear() async {
    await initialize();
    await _channel.invokeMethod<bool>('clearIndex');
  }

  List<SemanticSearchResult> _resultsFromRows(List<Object?>? rows) {
    return (rows ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(SemanticSearchResult.fromMap)
        .toList(growable: false);
  }

  Future<void> _handleNativeCallback(MethodCall call) async {
    // MethodChannel is bidirectional: this handler receives native progress
    // updates sent from MainActivity during gallery indexing.
    if (call.method == 'indexProgress') {
      final args = (call.arguments as Map).cast<Object?, Object?>();
      onIndexProgress?.call(IndexProgress.fromMap(args));
    }
  }
}

// Progress event for the current indexing batch.
class IndexProgress {
  const IndexProgress({
    required this.completed,
    required this.total,
    required this.indexed,
    required this.skipped,
    required this.failed,
    required this.currentId,
  });

  final int completed;
  final int total;
  final int indexed;
  final int skipped;
  final int failed;
  final String currentId;

  double get fraction => total == 0 ? 1 : completed / total;

  factory IndexProgress.fromMap(Map<Object?, Object?> map) {
    return IndexProgress(
      completed: map['completed']! as int,
      total: map['total']! as int,
      indexed: map['indexed']! as int,
      skipped: map['skipped']! as int,
      failed: map['failed']! as int,
      currentId: map['currentId']! as String,
    );
  }
}

// Summary returned after an indexing pass finishes.
class GalleryIndexSummary {
  const GalleryIndexSummary({
    required this.totalGalleryImages,
    required this.processed,
    required this.indexed,
    required this.skipped,
    required this.failed,
    required this.stored,
  });

  final int totalGalleryImages;
  final int processed;
  final int indexed;
  final int skipped;
  final int failed;
  final int stored;

  factory GalleryIndexSummary.fromMap(Map<Object?, Object?> map) {
    return GalleryIndexSummary(
      totalGalleryImages: map['totalGalleryImages']! as int,
      processed: map['processed']! as int,
      indexed: map['indexed']! as int,
      skipped: map['skipped']! as int,
      failed: map['failed']! as int,
      stored: map['stored']! as int,
    );
  }
}
