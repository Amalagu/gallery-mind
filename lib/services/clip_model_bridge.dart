import 'dart:typed_data';

import 'package:flutter/services.dart';

// Lower-level bridge for directly asking native Android to create embeddings.
// Most app screens use EmbeddingIndex instead; this class is useful for smoke
// tests or future features that need raw vector output.
class ClipModelBridge {
  ClipModelBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('gallerymind/clip');

  final MethodChannel _channel;
  bool _initialized = false;

  Future<void> initialize() async {
    // Loads the ONNX model sessions on the native side once.
    if (_initialized) return;
    await _channel.invokeMethod<bool>('initialize');
    _initialized = true;
  }

  Future<List<double>> embedText(String text) async {
    await initialize();
    final result = await _channel.invokeMethod<Object?>(
      'embedText',
      {'text': text},
    );
    return _asDoubleList(result);
  }

  Future<List<double>> embedImageBytes(Uint8List bytes) async {
    await initialize();
    final result = await _channel.invokeMethod<Object?>(
      'embedImageBytes',
      {'bytes': bytes},
    );
    return _asDoubleList(result);
  }

  Future<List<double>> embedImageAsset(String assetPath) async {
    await initialize();
    final result = await _channel.invokeMethod<Object?>(
      'embedImageAsset',
      {'assetPath': assetPath},
    );
    return _asDoubleList(result);
  }

  Future<void> close() async {
    if (!_initialized) return;
    await _channel.invokeMethod<bool>('close');
    _initialized = false;
  }

  List<double> _asDoubleList(Object? value) {
    // MethodChannel may decode numeric arrays in a few different Dart shapes,
    // so normalize them into a plain List<double>.
    if (value is Float64List) return value.toList(growable: false);
    if (value is Float32List) {
      return value.map((item) => item.toDouble()).toList(growable: false);
    }
    if (value is List) {
      return value
          .map((item) => (item as num).toDouble())
          .toList(growable: false);
    }
    throw StateError('Unexpected embedding result type: ${value.runtimeType}');
  }
}
