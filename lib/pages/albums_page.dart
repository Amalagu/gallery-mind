import 'package:flutter/material.dart';

import '../models/gallery_image.dart';
import '../services/embedding_index.dart';
import '../services/gallery_preferences.dart';
import '../widgets/gallery_image_view.dart';
import 'image_detail_page.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({
    super.key,
    required this.similarityThreshold,
  });

  final int similarityThreshold;

  @override
  State<AlbumsPage> createState() => AlbumsPageState();
}

class AlbumsPageState extends State<AlbumsPage> {
  final GalleryPreferences _preferences = GalleryPreferences();
  final EmbeddingIndex _index = EmbeddingIndex();

  bool _loading = true;
  List<GalleryImage> _favorites = const [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> reloadFavorites() => _loadFavorites();

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final favoriteIds = await _preferences.getFavoriteImageIds();
    final indexedImages = <GalleryImage>[];
    try {
      if (await _index.hasPhotoPermission()) {
        final records = await _index.getAllIndexedImages(limit: 5000);
        indexedImages.addAll(records.map(_imageFromRecord));
      }
    } catch (_) {
      // If native gallery access is unavailable, Favorites simply has no
      // resolvable device images to show.
    }
    final byId = <String, GalleryImage>{
      for (final image in indexedImages) image.id: image,
    };
    if (!mounted) return;
    setState(() {
      _favorites = [
        for (final id in favoriteIds)
          if (byId[id] != null) byId[id]!,
      ];
      _loading = false;
    });
  }

  GalleryImage _imageFromRecord(IndexedImageRecord record) {
    return GalleryImage(
      id: record.id,
      assetPath: record.uri,
      title: record.title.isEmpty ? 'Gallery Image' : record.title,
      description: record.description,
      date: _dateLabelForMillis(record.dateTakenMillis),
      location: 'Device Gallery',
      tags: record.tags,
      dateTakenMillis:
          record.dateTakenMillis == 0 ? null : record.dateTakenMillis,
    );
  }

  String _dateLabelForMillis(int millis) {
    if (millis <= 0) return 'Undated';
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) return 'Today';
    if (DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('albums'),
      color: const Color(0xFF060710),
      child: RefreshIndicator(
        color: const Color(0xFF8790FF),
        backgroundColor: const Color(0xFF111424),
        onRefresh: _loadFavorites,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Albums',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Favorite images saved as a lightweight list.',
                      style: TextStyle(
                        color: Color(0xFF9BA1B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FavoritesAlbumCard(
                      images: _favorites,
                      loading: _loading,
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Favorites',
                      style: TextStyle(
                        color: Color(0xFFE8EAFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_favorites.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyFavorites(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 118),
                sliver: SliverGrid.builder(
                  itemCount: _favorites.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    return _FavoriteTile(
                      image: _favorites[index],
                      images: _favorites,
                      index: index,
                      similarityThreshold: widget.similarityThreshold,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesAlbumCard extends StatelessWidget {
  const _FavoritesAlbumCard({
    required this.images,
    required this.loading,
  });

  final List<GalleryImage> images;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        color: const Color(0xFF10131D),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF282D3D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isEmpty)
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF111424)),
            )
          else
            Row(
              children: [
                for (final image in images.take(3))
                  Expanded(
                    child: GalleryImageView(uri: image.assetPath),
                  ),
              ],
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.78),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF8790FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loading
                        ? 'Loading Favorites'
                        : 'Favorites • ${images.length} image${images.length == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.image,
    required this.images,
    required this.index,
    required this.similarityThreshold,
  });

  final GalleryImage image;
  final List<GalleryImage> images;
  final int index;
  final int similarityThreshold;

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageDetailPage(
            image: image,
            heroTag: 'favorites-${image.id}-$index',
            images: images,
            heroTags: [
              for (var i = 0; i < images.length; i += 1)
                'favorites-${images[i].id}-$i',
            ],
            initialIndex: index,
            heroPrefix: 'favorites',
            similarityThreshold: similarityThreshold,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return child;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Hero(
          tag: 'favorites-${image.id}-$index',
          child: GalleryImageView(uri: image.assetPath),
        ),
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              color: Color(0xFF8790FF),
              size: 34,
            ),
            SizedBox(height: 14),
            Text(
              'No favorites yet',
              style: TextStyle(
                color: Color(0xFFE6E8FF),
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Open an image and tap Favorite to save it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9BA1B8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
