import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/embedding_index.dart';

// Shared image widget for both bundled assets and real Android gallery images.
// Real gallery images arrive as content:// URIs, which Flutter cannot decode
// directly without asking native Android for bytes first.
class GalleryImageView extends StatelessWidget {
  const GalleryImageView({
    super.key,
    required this.uri,
    this.fit = BoxFit.cover,
    this.maxSize = 720,
  });

  final String uri;
  final BoxFit fit;
  final int maxSize;

  // The byte cache prevents the same thumbnail from being fetched/decoded again
  // every time Flutter rebuilds a grid tile.
  static final Map<String, Future<Uint8List>> _byteCache = {};
  static final EmbeddingIndex _index = EmbeddingIndex();

  @override
  Widget build(BuildContext context) {
    // Sample/demo images are normal Flutter assets, so they can be shown
    // directly without MethodChannel work.
    if (!uri.startsWith('content://')) {
      return Image.asset(uri, fit: fit, gaplessPlayback: true);
    }

    final future = _byteCache.putIfAbsent(
      '$uri-$maxSize',
      // Native Android loads and downscales the content:// image before sending
      // JPEG bytes back to Flutter.
      () => _index.getImageBytes(uri, maxSize: maxSize),
    );

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(snapshot.data!, fit: fit, gaplessPlayback: true);
        }
        return const ColoredBox(
          color: Color(0xFF10121C),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}
