import 'package:flutter/services.dart';

class GalleryPreferences {
  GalleryPreferences({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('gallerymind/clip');

  static const int defaultSimilarityThreshold = 70;
  static const bool defaultShowFilenameMatches = true;

  static const String _similarityThresholdKey =
      'similar_image_threshold_percent';
  static const String _showFilenameMatchesKey = 'show_filename_matches';
  static const String _favoriteImageIdsKey = 'favorite_image_ids';

  final MethodChannel _channel;

  Future<int> getSimilarityThreshold() async {
    final value = await _channel.invokeMethod<int>(
      'getIntPreference',
      {
        'key': _similarityThresholdKey,
        'defaultValue': defaultSimilarityThreshold,
      },
    );
    return (value ?? defaultSimilarityThreshold).clamp(70, 100).toInt();
  }

  Future<void> setSimilarityThreshold(int value) async {
    final normalized = (value / 5).round() * 5;
    await _channel.invokeMethod<bool>(
      'setIntPreference',
      {
        'key': _similarityThresholdKey,
        'value': normalized.clamp(70, 100),
      },
    );
  }

  Future<bool> getShowFilenameMatches() async {
    final value = await _channel.invokeMethod<bool>(
      'getBoolPreference',
      {
        'key': _showFilenameMatchesKey,
        'defaultValue': defaultShowFilenameMatches,
      },
    );
    return value ?? defaultShowFilenameMatches;
  }

  Future<void> setShowFilenameMatches(bool value) async {
    await _channel.invokeMethod<bool>(
      'setBoolPreference',
      {
        'key': _showFilenameMatchesKey,
        'value': value,
      },
    );
  }

  Future<Set<String>> getFavoriteImageIds() async {
    final values = await _channel.invokeMethod<List<Object?>>(
      'getStringListPreference',
      {
        'key': _favoriteImageIdsKey,
      },
    );
    return (values ?? const []).whereType<String>().toSet();
  }

  Future<bool> isFavorite(String imageId) async {
    final favorites = await getFavoriteImageIds();
    return favorites.contains(imageId);
  }

  Future<void> setFavorite(String imageId, bool favorite) async {
    final favorites = await getFavoriteImageIds();
    if (favorite) {
      favorites.add(imageId);
    } else {
      favorites.remove(imageId);
    }
    await _channel.invokeMethod<bool>(
      'setStringListPreference',
      {
        'key': _favoriteImageIdsKey,
        'value': favorites.toList(growable: false)..sort(),
      },
    );
  }
}
