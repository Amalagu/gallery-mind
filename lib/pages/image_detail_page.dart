import 'package:flutter/material.dart';

import '../models/gallery_image.dart';
import '../services/embedding_index.dart';
import '../services/gallery_preferences.dart';
import '../widgets/gallery_image_view.dart';

// Full-screen viewer for a selected image. It supports Hero animation from the
// grid, left/right swiping through the source list, and a draggable detail sheet.
class ImageDetailPage extends StatefulWidget {
  const ImageDetailPage({
    super.key,
    required this.image,
    required this.heroTag,
    List<GalleryImage>? images,
    List<String>? heroTags,
    this.initialIndex = 0,
    this.heroPrefix = 'gallery-image',
    this.similarityThreshold = GalleryPreferences.defaultSimilarityThreshold,
  })  : images = images ?? const [],
        heroTags = heroTags ?? const [];

  final GalleryImage image;
  final String heroTag;
  final List<GalleryImage> images;
  final List<String> heroTags;
  final int initialIndex;
  final String heroPrefix;
  final int similarityThreshold;

  @override
  State<ImageDetailPage> createState() => _ImageDetailPageState();
}

class _ImageDetailPageState extends State<ImageDetailPage> {
  late final PageController _pageController;
  late int _currentIndex;

  List<GalleryImage> get _images =>
      // If a caller only provides one image, still treat it as a one-page list
      // so the rest of the detail code can stay consistent.
      widget.images.isEmpty ? [widget.image] : widget.images;
  GalleryImage get _currentImage =>
      _images[_currentIndex.clamp(0, _images.length - 1).toInt()];

  String _heroTagFor(int index, GalleryImage image) {
    // The first opened image must use the exact Hero tag from the grid. For
    // swiped images, use the matching tag list when the caller supplied one.
    if (widget.images.isEmpty || _images.length == 1) return widget.heroTag;
    if (index >= 0 && index < widget.heroTags.length) {
      return widget.heroTags[index];
    }
    return '${widget.heroPrefix}-${image.id}-$index';
  }

  @override
  void initState() {
    super.initState();
    // Clamp protects the detail page if a source index is stale or out of range.
    final safeInitialIndex =
        widget.initialIndex.clamp(0, _images.length - 1).toInt();
    _currentIndex = safeInitialIndex;
    _pageController = PageController(initialPage: safeInitialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060710),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Stack(
              children: [
                Positioned.fill(
                  // PageView is what allows horizontal swiping between all
                  // images from the grid/search section that opened this page.
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _images.length,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final image = _images[index];
                      return _HeroImage(
                        image: image,
                        heroTag: _heroTagFor(index, image),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _DetailTopBar(image: _currentImage),
                ),
                DraggableScrollableSheet(
                  // The sheet starts as a compact details card, can snap to a
                  // middle reading height, and can expand over nearly the whole
                  // image to show more matches.
                  initialChildSize: 0.34,
                  minChildSize: 0.27,
                  maxChildSize: 0.96,
                  snap: true,
                  snapSizes: const [0.34, 0.62, 0.96],
                  builder: (context, scrollController) {
                    return _DetailSheet(
                      key: ValueKey(_currentImage.id),
                      image: _currentImage,
                      similarityThreshold: widget.similarityThreshold,
                      scrollController: scrollController,
                    );
                  },
                ),
                // TO BE IMPLEMENTED: Action bar with buttons for sharing, favoriting, and more. This is a great place to show how the detail page can have interactive elements that relate to the current image.
                /* const Positioned(
                  left: 34,
                  right: 34,
                  bottom: 12,
                  child: DetailActionBar(),
                ), */
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({
    required this.image,
    required this.heroTag,
  });

  final GalleryImage image;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // BoxFit.contain prevents tall or wide photos from being cropped during
        // the Hero transition and detail view.
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: constraints.maxHeight * 0.76,
            width: double.infinity,
            child: Hero(
              tag: heroTag,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFF04050B),
                    child: GalleryImageView(
                      uri: image.assetPath,
                      fit: BoxFit.contain,
                      maxSize: 1080,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.08),
                          Colors.transparent,
                          const Color(0xFF060710).withOpacity(0.48),
                        ],
                        stops: const [0, 0.52, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.image});

  final GalleryImage image;

  Future<void> _shareImage(BuildContext context) async {
    try {
      // Sharing is handled by Android because content:// gallery URIs need
      // native Intent permissions before another app can read them.
      await EmbeddingIndex().shareImage(image.assetPath);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not share this image'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          _RoundIconButton(
            icon: Icons.share_rounded,
            onTap: () => _shareImage(context),
          ),

          // TO BE IMPLEMENTED: Right button could be a favorite toggle or a menu for more actions. This is a great place to show how the top bar can have multiple buttons with different functions.
          /* const SizedBox(width: 12),
          _RoundIconButton(
            icon: Icons.more_horiz_rounded,
            onTap: () {},
          ), */
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.54),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    super.key,
    required this.image,
    required this.similarityThreshold,
    required this.scrollController,
  });

  final GalleryImage image;
  final int similarityThreshold;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // This sheet is scrollable inside DraggableScrollableSheet, so dragging the
    // handle first expands the sheet and then scrolls the details.
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF070811),
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: ListView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 116),
        children: [
          const _PageHandle(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ImageCopy(image: image)),
              //TO BE IMPLEMENTED: Favorite button with native persistence. This is a great spot to show how the detail sheet can have multiple columns to take advantage of wider screen space.
              const SizedBox(width: 12),
              _FavoriteButton(imageId: image.id),
            ],
          ),
          //TO BE IMPLEMENTED: Tapping a tag should open a search for that tag, so these would be great to show off as Chips with tap effects. If an image has no tags, this row can be hidden to save space.
          /* const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: image.tags.map((tag) => _TagPill(label: tag)).toList(),
          ), */
          const SizedBox(height: 24),
          _MetadataRow(image: image),
          const SizedBox(width: 12),
          const Divider(color: Color(0xFF1A1F2E)),
          const SizedBox(width: 12),
          _SemanticMatches(
            currentImage: image,
            similarityThreshold: similarityThreshold,
          ),
          const SizedBox(height: 24),
          //_MetadataRow(image: image),
        ],
      ),
    );
  }
}

class _PageHandle extends StatelessWidget {
  const _PageHandle();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return Container(
              width: index == 2 ? 7 : 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: index == 2
                    ? const Color(0xFF8E95B6)
                    : const Color(0xFF384057),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        const SizedBox(height: 9),
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFF2D2F3B),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _ImageCopy extends StatelessWidget {
  const _ImageCopy({required this.image});

  final GalleryImage image;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /* const Row(
          children: [
            Icon(Icons.auto_awesome_rounded,
                color: Color(0xFF8790FF), size: 16),
            SizedBox(width: 7),
            Text(
              'GALLERYMIND',
              style: TextStyle(
                color: Color(0xFF8790FF),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ), */
        const SizedBox(height: 7),
        Text(
          image.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.00,
          ),
        ),

        //TO BE IMPLEMENTED: Description from the image's metadata or an AI caption. This is a great place to show off multi-line text and how it interacts with the rest of the sheet's content.
        /* const SizedBox(height: 9),
        Text(
          '"${image.description}"',
          style: const TextStyle(
            color: Color(0xFFB2B6CA),
            fontSize: 13,
            fontStyle: FontStyle.italic,
            height: 1.35,
            letterSpacing: 0,
          ),
        ), */
      ],
    );
  }
}

class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.imageId});

  final String imageId;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  final GalleryPreferences _preferences = GalleryPreferences();
  bool _favorite = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  @override
  void didUpdateWidget(covariant _FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId) _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final favorite = await _preferences.isFavorite(widget.imageId);
    if (!mounted) return;
    setState(() {
      _favorite = favorite;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_loading) return;
    final next = !_favorite;
    setState(() => _favorite = next);
    await _preferences.setFavorite(widget.imageId, next);
  }

  @override
  Widget build(BuildContext context) {
    final background =
        _favorite ? const Color(0xFF8790FF) : const Color(0xFF171923);
    final iconColor =
        _favorite ? const Color(0xFF070812) : const Color(0xFFA4ACBF);
    final labelColor =
        _favorite ? const Color(0xFFE1E4FF) : const Color(0xFF8E94AA);

    return GestureDetector(
      onTap: _toggleFavorite,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _favorite
                    ? const Color(0xFFB7BCFF)
                    : const Color(0xFF2B2E3A),
              ),
            ),
            child: Icon(
              _favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Favorite',
            style: TextStyle(
              color: labelColor,
              fontSize: 9,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
/*
class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 27,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF171923),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF2B2E3A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 7, color: Color(0xFF8790FF)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE0E3F2),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
} */

class _SemanticMatches extends StatelessWidget {
  const _SemanticMatches({
    required this.currentImage,
    required this.similarityThreshold,
  });

  final GalleryImage currentImage;
  final int similarityThreshold;

  Future<List<GalleryImage>> _loadMatches() async {
    // Detail suggestions use a stricter threshold than text search. These are
    // image-to-image matches, so 70% keeps the row visually related.
    final threshold = similarityThreshold / 100.0;
    try {
      final results = await EmbeddingIndex().findSimilarImages(
        currentImage.id,
        threshold: threshold,
        limit: 30,
      );
      if (results.isEmpty) return const [];
      // Convert native similarity results back into the same GalleryImage model
      // used by normal tiles and the detail viewer.
      return results
          .map(
            (result) => GalleryImage(
              id: result.record.id,
              assetPath: result.record.uri,
              title: result.record.title.isEmpty
                  ? 'Gallery Image'
                  : result.record.title,
              description: result.record.description,
              date: _dateLabelForMillis(result.record.dateTakenMillis),
              location: 'Device Gallery',
              tags: result.record.tags,
              dateTakenMillis: result.record.dateTakenMillis == 0
                  ? null
                  : result.record.dateTakenMillis,
              matchPercent: (result.combinedScore * 100).round().clamp(0, 100),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Similar Images',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 3),
                  /* Row(
                    children: [
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171B3C),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF353C7B)),
                        ),
                        child: Center(
                          child: Text(
                            ' Above $similarityThreshold%+ threshold similarity',
                            style: const TextStyle(
                              color: Color(0xFFBFC4FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ), */
                ],
              ),
            ),
            /* Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF171B3C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF353C7B)),
              ),
              child: Center(
                child: Text(
                  '$similarityThreshold%+',
                  style: const TextStyle(
                    color: Color(0xFFBFC4FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ), */
            SizedBox(width: 8),
            /* TextButton.icon(
              onPressed: () {},
              icon: const Icon(
                Icons.auto_awesome_rounded,
                size: 13,
                color: Color(0xFF8790FF),
              ),
              label: const Text('Find more'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9AA1FF),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                padding: EdgeInsets.zero,
                minimumSize: const Size(82, 30),
              ),
            ), */
            //here
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF8790FF), size: 16),
                SizedBox(width: 7),
                Text(
                  'GALLERYMIND',
                  style: TextStyle(
                    color: Color(0xFF8790FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<GalleryImage>>(
          // FutureBuilder lets this section load native matches without
          // blocking the rest of the detail sheet.
          future: _loadMatches(),
          builder: (context, snapshot) {
            final matches = snapshot.data;
            if (matches == null) {
              return const SizedBox(
                height: 90,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (matches.isEmpty) return const _SimilarityEmptyState();
            return GridView.builder(
              itemCount: matches.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final match = matches[index];
                return _MatchThumb(
                  image: match,
                  heroTag: 'semantic-match-${currentImage.id}-${match.id}',
                  images: matches,
                  heroTags: [
                    for (final candidate in matches)
                      'semantic-match-${currentImage.id}-${candidate.id}',
                  ],
                  initialIndex: index,
                  similarityThreshold: similarityThreshold,
                );
              },
            );
          },
        ),
      ],
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
}

class _MatchThumb extends StatelessWidget {
  const _MatchThumb({
    required this.image,
    required this.heroTag,
    required this.images,
    required this.heroTags,
    required this.initialIndex,
    required this.similarityThreshold,
  });

  final GalleryImage image;
  final String heroTag;
  final List<GalleryImage> images;
  final List<String> heroTags;
  final int initialIndex;
  final int similarityThreshold;

  void _openMatch(BuildContext context) {
    // Replace instead of stacking detail pages endlessly. The user can still
    // navigate through the match list by swiping inside the new detail page.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageDetailPage(
            image: image,
            heroTag: heroTag,
            images: images,
            heroTags: heroTags,
            initialIndex: initialIndex,
            similarityThreshold: similarityThreshold,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('semantic-match-${image.id}'),
      onTap: () => _openMatch(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: GalleryImageView(uri: image.assetPath),
            ),
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF092E2B),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Center(
                  child: Text(
                    '${image.matchPercent}%',
                    style: const TextStyle(
                      color: Color(0xFF3EF5B6),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarityEmptyState extends StatelessWidget {
  const _SimilarityEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF11131D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272B3A)),
      ),
      child: const Center(
        child: Text(
          'No images above this threshold yet',
          style: TextStyle(
            color: Color(0xFF8E94AA),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.image});

  final GalleryImage image;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetadataItem(
            value: image.date,
            label: '11:42 PM',
          ),
        ),
        Container(
          width: 1,
          height: 38,
          color: const Color(0xFF242836),
        ),
        Expanded(
          child: _MetadataItem(
            value: image.location,
            label: 'Shibuya District',
          ),
        ),
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          /* const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8E94AA),
              fontSize: 10,
              letterSpacing: 0,
            ),
          ), */
        ],
      ),
    );
  }
}
