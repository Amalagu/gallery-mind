import 'package:flutter/material.dart';

import '../data/sample_gallery.dart';
import '../models/gallery_image.dart';
import '../services/embedding_index.dart';
import '../widgets/gallery_image_view.dart';
import 'image_detail_page.dart';

// HomePage is the main gallery and search screen. It shows all indexed images
// by date, runs semantic filename searches, and opens image details.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // Expanded search mode loads results in batches so a large gallery does not
  // build thousands of tiles at once.
  static const int _expandedPageSize = 36;
  static const int _backgroundIndexBatchSize = 100;
  static const int _progressiveReloadEvery = 12;

  final EmbeddingIndex _index = EmbeddingIndex();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // _images is the normal gallery list. The two result lists are deliberately
  // separate because semantic CLIP results and literal filename matches have
  // different meanings and thresholds.
  List<GalleryImage> _images = sampleGalleryImages;
  List<GalleryImage> _semanticResults = const [];
  List<GalleryImage> _filenameResults = const [];
  String _currentQuery = '';
  bool _loading = true;
  bool _searching = false;
  bool _refreshing = false;
  bool _showingSearchResults = false;
  bool _disposed = false;
  bool _backgroundIndexStarted = false;
  bool _backgroundIndexingActive = false;
  bool _indexingCardCollapsed = false;
  bool _indexingCompleteVisible = false;
  SearchResultSection? _expandedSection;
  int _semanticVisibleCount = _expandedPageSize;
  int _filenameVisibleCount = _expandedPageSize;
  int _indexingStored = 0;
  int _indexingTotal = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchTextChanged);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _scrollController.addListener(_handleScroll);
    _loadIndexedImages().then((_) {
      if (mounted) _startBackgroundIndexing();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveSearch =>
      _searchController.text.trim().isNotEmpty || _showingSearchResults;
  bool get _isSearchShellActive =>
      _searchFocusNode.hasFocus || _hasActiveSearch;
  bool get _isPlainHomeState => !_isSearchShellActive;
  bool get _showIndexingCard =>
      _backgroundIndexingActive || _indexingCompleteVisible;

  double get _indexingFraction {
    if (_indexingTotal <= 0) return 0;
    return (_indexingStored / _indexingTotal).clamp(0.0, 1.0);
  }

  void _handleSearchTextChanged() {
    // The clear button appears/disappears as the user types.
    if (mounted) setState(() {});
  }

  void _handleSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_searchFocusNode.hasFocus) {
      // After the header animates upward, ask for focus again so the keyboard
      // stays open instead of dropping during the layout change.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  void _handleScroll() {
    // Lazy-load more results only when an expanded result section is close to
    // the bottom of the scroll view.
    if (_expandedSection == null ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 700) {
      return;
    }
    setState(() {
      if (_expandedSection == SearchResultSection.semantic) {
        _semanticVisibleCount = (_semanticVisibleCount + _expandedPageSize)
            .clamp(
              0,
              _semanticResults.length,
            )
            .toInt();
      } else {
        _filenameVisibleCount = (_filenameVisibleCount + _expandedPageSize)
            .clamp(
              0,
              _filenameResults.length,
            )
            .toInt();
      }
    });
  }

  Future<void> _loadIndexedImages({bool resetViewState = true}) async {
    try {
      // Pull the native SQLite records into Dart models for the normal gallery.
      // The sample images are a fallback for development or empty indexes.
      final records = await _index.getAllIndexedImages(limit: 5000);
      if (!mounted) return;
      setState(() {
        _images = records.isEmpty
            ? sampleGalleryImages
            : records.map(_imageFromRecord).toList(growable: false);
        _indexingStored = records.length;
        _loading = false;
        if (resetViewState) {
          _showingSearchResults = false;
          _expandedSection = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _images = sampleGalleryImages;
        _loading = false;
        if (resetViewState) {
          _showingSearchResults = false;
          _expandedSection = null;
        }
      });
    }
  }

  Future<void> _startBackgroundIndexing() async {
    if (_backgroundIndexStarted || _disposed) return;
    _backgroundIndexStarted = true;

    setState(() {
      _backgroundIndexingActive = true;
      _indexingCompleteVisible = false;
      _indexingCardCollapsed = false;
    });

    try {
      while (!_disposed) {
        var lastReloadAt = 0;
        final storedBeforeBatch = _indexingStored;
        final summary = await _index.indexNewGalleryImages(
          limit: _backgroundIndexBatchSize,
          onProgress: (progress) {
            if (_disposed || !mounted) return;
            final estimatedTotal = _indexingTotal > 0
                ? _indexingTotal
                : storedBeforeBatch + progress.total;
            setState(() {
              _indexingTotal = estimatedTotal;
              _indexingStored = (storedBeforeBatch + progress.indexed)
                  .clamp(0, estimatedTotal == 0 ? 1 << 30 : estimatedTotal)
                  .toInt();
            });

            if (progress.indexed > 0 &&
                progress.indexed - lastReloadAt >= _progressiveReloadEvery) {
              lastReloadAt = progress.indexed;
              _loadIndexedImages(resetViewState: false);
            }
          },
        );

        if (_disposed || !mounted) return;
        setState(() {
          _indexingTotal = summary.totalGalleryImages;
          _indexingStored = summary.stored;
        });
        await _loadIndexedImages(resetViewState: false);

        if (summary.indexed == 0 ||
            summary.processed == 0 ||
            summary.stored >= summary.totalGalleryImages) {
          break;
        }

        // Yield briefly between chunks so taps, scrolling, and route transitions
        // get breathing room while the remaining gallery continues indexing.
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      if (_disposed || !mounted) return;
      setState(() {
        _backgroundIndexingActive = false;
        _indexingCompleteVisible = _indexingTotal > 0;
        _indexingStored = _indexingTotal > 0 ? _indexingTotal : _indexingStored;
      });

      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (_disposed || !mounted) return;
      setState(() => _indexingCompleteVisible = false);
    } catch (_) {
      if (_disposed || !mounted) return;
      setState(() {
        _backgroundIndexingActive = false;
        _indexingCompleteVisible = false;
      });
    }
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      await _clearSearch();
      return;
    }

    setState(() {
      // A new submitted query always resets expansion/pagination so old search
      // state cannot leak into the next result set.
      _searching = true;
      _showingSearchResults = true;
      _expandedSection = null;
      _currentQuery = trimmed;
      _semanticResults = const [];
      _filenameResults = const [];
      _semanticVisibleCount = _expandedPageSize;
      _filenameVisibleCount = _expandedPageSize;
    });
    // Semantic search uses the CLIP text embedding. Filename matching is a
    // separate literal text search over stored image titles only.
    final semanticFuture =
        _index.searchText(trimmed, limit: 240, threshold: 0.5);
    final filenameFuture = _loadFilenameMatches(trimmed);
    final semanticRows = await semanticFuture;
    final filenameMatches = await filenameFuture;
    if (!mounted) return;
    setState(() {
      _semanticResults = semanticRows
          .map(
            (result) => _imageFromRecord(
              result.record,
              matchPercent: (result.combinedScore * 100).round().clamp(0, 100),
            ),
          )
          .toList(growable: false);
      _filenameResults = filenameMatches;
      _searching = false;
      _showingSearchResults = true;
      _expandedSection = null;
      _semanticVisibleCount = _expandedPageSize;
      _filenameVisibleCount = _expandedPageSize;
    });
  }

  void _runChipSearch(String query) {
    // Chips behave exactly like the user typed the query and pressed search.
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    _runSearch(query);
  }

  Future<List<GalleryImage>> _loadFilenameMatches(String query) async {
    try {
      // Filename search intentionally ignores captions/descriptions. Those are
      // already represented in the semantic embedding pipeline.
      final records = await _index.getAllIndexedImages(limit: 5000);
      final normalizedQuery = query.toLowerCase();
      return records
          .where(
              (record) => record.title.toLowerCase().contains(normalizedQuery))
          .map((record) => _imageFromRecord(record))
          .toList(growable: false);
    } catch (_) {
      final normalizedQuery = query.toLowerCase();
      return sampleGalleryImages
          .where((image) => image.title.toLowerCase().contains(normalizedQuery))
          .toList(growable: false);
    }
  }

  Future<void> _clearSearch() async {
    // Clearing returns Home to the normal date-grouped gallery view.
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.clear();
    setState(() {
      _searching = false;
      _showingSearchResults = false;
      _expandedSection = null;
      _currentQuery = '';
      _semanticResults = const [];
      _filenameResults = const [];
      _loading = true;
    });
    await _loadIndexedImages();
  }

  Future<void> _refreshGalleryIndex() async {
    if (_searching || _refreshing) return;
    // Pull-to-refresh asks native Android to scan MediaStore for new images and
    // index only the records that are not already stored.
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.clear();
    setState(() {
      _refreshing = true;
      _showingSearchResults = false;
      _expandedSection = null;
      _currentQuery = '';
      _semanticResults = const [];
      _filenameResults = const [];
    });

    var indexed = 0;
    try {
      final summary = await _index.indexNewGalleryImages();
      indexed = summary.indexed;
      await _loadIndexedImages();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              indexed == 0
                  ? 'GalleryMind is up to date'
                  : 'Indexed $indexed new image${indexed == 1 ? '' : 's'}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not refresh the gallery index'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<bool> handleSystemBack() async {
    // Return true when Home consumed the back press so GalleryShell does not
    // exit the app. This order closes the most specific UI state first.
    if (_expandedSection != null) {
      setState(() {
        _expandedSection = null;
        _semanticVisibleCount = _expandedPageSize;
        _filenameVisibleCount = _expandedPageSize;
      });
      return true;
    } else if (_hasActiveSearch) {
      await _clearSearch();
      return true;
    } else if (_searchFocusNode.hasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
      return true;
    }
    return false;
  }

  Future<void> resetToInitialHome() async {
    // Used by the bottom Home tab. It should behave like a gentle "return home"
    // action from search focus, search results, or expanded search sections.
    if (_expandedSection != null || _hasActiveSearch) {
      await _clearSearch();
    } else if (_searchFocusNode.hasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) setState(() {});
    }

    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _expandSection(SearchResultSection section) {
    // "See More" does not push a new route. It just changes this page's state
    // so the selected result type takes over the content area below search.
    setState(() {
      _expandedSection = section;
      _semanticVisibleCount =
          _expandedPageSize.clamp(0, _semanticResults.length).toInt();
      _filenameVisibleCount =
          _expandedPageSize.clamp(0, _filenameResults.length).toInt();
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  GalleryImage _imageFromRecord(
    IndexedImageRecord record, {
    int matchPercent = 92,
  }) {
    // Native records are intentionally plain maps; this converts them into the
    // richer model expected by the Flutter widgets.
    final dateLabel = _dateLabelForMillis(record.dateTakenMillis);
    return GalleryImage(
      id: record.id,
      assetPath: record.uri,
      title: record.title.isEmpty ? 'Gallery Image' : record.title,
      description: record.description,
      date: dateLabel,
      location: 'Device Gallery',
      tags: record.tags,
      dateTakenMillis:
          record.dateTakenMillis == 0 ? null : record.dateTakenMillis,
      matchPercent: matchPercent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (!_isSearchShellActive)
          SliverPersistentHeader(
            pinned: true,
            delegate: FixedHeightHeaderDelegate(
              height: HomeTopChrome.height(
                showIndexingCard: _showIndexingCard,
                indexingCardCollapsed: _indexingCardCollapsed,
              ),
              child: HomeTopChrome(
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
                searching: _searching || _refreshing,
                onSubmitted: _runSearch,
                onClear: _clearSearch,
                onChipSelected: _runChipSearch,
                showIndexingCard: _showIndexingCard,
                indexingCardCollapsed: _indexingCardCollapsed,
                indexingComplete: _indexingCompleteVisible,
                indexingStored: _indexingStored,
                indexingTotal: _indexingTotal,
                indexingFraction: _indexingFraction,
                onToggleIndexingCard: () {
                  setState(() {
                    _indexingCardCollapsed = !_indexingCardCollapsed;
                  });
                },
              ),
            ),
          )
        else
          SliverPersistentHeader(
            pinned: true,
            delegate: FixedHeightHeaderDelegate(
              height: SearchTopChrome.height(
                showIndexingCard: _showIndexingCard,
                indexingCardCollapsed: _indexingCardCollapsed,
              ),
              child: SearchTopChrome(
                controller: _searchController,
                focusNode: _searchFocusNode,
                searching: _searching || _refreshing,
                onSubmitted: _runSearch,
                onClear: _clearSearch,
                showIndexingCard: _showIndexingCard,
                indexingCardCollapsed: _indexingCardCollapsed,
                indexingComplete: _indexingCompleteVisible,
                indexingStored: _indexingStored,
                indexingTotal: _indexingTotal,
                indexingFraction: _indexingFraction,
                onToggleIndexingCard: () {
                  setState(() {
                    _indexingCardCollapsed = !_indexingCardCollapsed;
                  });
                },
              ),
            ),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_searching)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_images.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No indexed matches yet',
                style: TextStyle(
                  color: Color(0xFFAEB4CA),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        else if (_showingSearchResults)
          ..._searchResultSlivers()
        else
          ..._dateSectionSlivers(_images),
      ],
    );

    return ColoredBox(
      key: const ValueKey('home'),
      color: const Color(0xFF060710),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        child: _isPlainHomeState
            ? RefreshIndicator(
                color: const Color(0xFF8790FF),
                backgroundColor: const Color(0xFF111424),
                onRefresh: _refreshGalleryIndex,
                child: scrollView,
              )
            : scrollView,
      ),
    );
  }

  List<Widget> _dateSectionSlivers(List<GalleryImage> images) {
    // Build one title plus one grid for each date group, matching the phone
    // gallery-style layout.
    final sections = _groupImagesByDate(images);
    final slivers = <Widget>[];
    for (var index = 0; index < sections.length; index += 1) {
      final section = sections[index];
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 26),
          sliver: SliverToBoxAdapter(
            child: GallerySectionTitle(title: section.title),
          ),
        ),
      );
      slivers.add(
        GalleryGrid(
          images: section.images,
          topPadding: 14,
          bottomPadding: index == sections.length - 1 ? 112 : 0,
          sourceImages: images,
        ),
      );
    }
    return slivers;
  }

  List<Widget> _searchResultSlivers() {
    // Search results have three visual modes: semantic expanded, filename
    // expanded, or the default dual-section preview.
    if (_expandedSection == SearchResultSection.semantic) {
      final visible = _semanticResults.take(_semanticVisibleCount).toList();
      return _expandedResultSlivers(
        title: 'Semantic Matches',
        images: visible,
        totalCount: _semanticResults.length,
      );
    }
    if (_expandedSection == SearchResultSection.filename) {
      final visible = _filenameResults.take(_filenameVisibleCount).toList();
      return _expandedResultSlivers(
        title: 'Filename Matches',
        images: visible,
        totalCount: _filenameResults.length,
      );
    }

    if (_semanticResults.isEmpty && _filenameResults.isEmpty) {
      // Empty searches get a friendly full-screen message instead of blank
      // sections or placeholder tiles.
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF8790FF),
                    size: 30,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No matches for "$_currentQuery"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFE6E8FF),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Try a broader phrase or refresh your gallery index.',
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
          ),
        ),
      ];
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Padding(
            key: ValueKey(_currentQuery),
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Results for "$_currentQuery"',
              style: const TextStyle(
                color: Color(0xFF8F96B8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    ];
    if (_semanticResults.isNotEmpty) {
      slivers.addAll([
        const SliverToBoxAdapter(
          child: GallerySectionTitle(title: 'Semantic Matches'),
        ),
        SearchPreviewGrid(
          images: _semanticResults,
          previewLimit: 8,
          topPadding: 14,
          bottomPadding: _filenameResults.isEmpty ? 112 : 0,
          onSeeMore: () => _expandSection(SearchResultSection.semantic),
          heroPrefix: 'semantic-result',
        ),
      ]);
    }
    if (_filenameResults.isNotEmpty) {
      slivers.addAll([
        if (_semanticResults.isNotEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
        const SliverToBoxAdapter(
          child: GallerySectionTitle(title: 'Filename Matches'),
        ),
        SearchPreviewGrid(
          images: _filenameResults,
          previewLimit: 5,
          topPadding: 14,
          bottomPadding: 112,
          onSeeMore: () => _expandSection(SearchResultSection.filename),
          heroPrefix: 'filename-result',
        ),
      ]);
    }
    return slivers;
  }

  List<Widget> _expandedResultSlivers({
    required String title,
    required List<GalleryImage> images,
    required int totalCount,
  }) {
    // Expanded sections reuse GalleryGrid and append a loader when more items
    // are available for lazy pagination.
    return [
      SliverToBoxAdapter(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: GallerySectionTitle(
            key: ValueKey(title),
            title: title,
          ),
        ),
      ),
      if (totalCount == 0)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'No matches yet',
              style: TextStyle(
                color: Color(0xFFAEB4CA),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        )
      else ...[
        GalleryGrid(
          images: images,
          topPadding: 14,
          bottomPadding: images.length >= totalCount ? 112 : 24,
          sourceImages: images,
          heroPrefix: 'expanded-result',
        ),
        if (images.length < totalCount)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 112),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    ];
  }

  List<GalleryDateSection> _groupImagesByDate(List<GalleryImage> images) {
    // Native records are already sorted newest-first, so grouping can be a
    // simple single pass that starts a new section when the label changes.
    final sections = <GalleryDateSection>[];
    for (final image in images) {
      final title = image.dateTakenMillis == null
          ? image.date
          : _dateLabelForMillis(image.dateTakenMillis!);
      if (sections.isEmpty || sections.last.title != title) {
        sections.add(GalleryDateSection(title: title, images: [image]));
      } else {
        sections.last.images.add(image);
      }
    }
    return sections;
  }

  String _dateLabelForMillis(int millis) {
    // Convert Android MediaStore timestamps into user-friendly section titles.
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

class GalleryDateSection {
  GalleryDateSection({required this.title, required this.images});

  final String title;
  final List<GalleryImage> images;
}

// Tracks which result source is expanded after pressing "See More".
enum SearchResultSection { semantic, filename }

class SearchPreviewGrid extends StatelessWidget {
  const SearchPreviewGrid({
    super.key,
    required this.images,
    required this.previewLimit,
    required this.onSeeMore,
    required this.heroPrefix,
    required this.topPadding,
    this.bottomPadding = 0,
  });

  final List<GalleryImage> images;
  final int previewLimit;
  final VoidCallback onSeeMore;
  final String heroPrefix;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    // The preview grid shows a fixed number of real images and only adds "See
    // More" when there are additional results to reveal.
    final hasMore = images.length > previewLimit;
    final itemCount = hasMore ? previewLimit + 1 : images.length;
    return SliverPadding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      sliver: SliverGrid.builder(
        itemCount: itemCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          if (hasMore && index == itemCount - 1) {
            return SeeMoreResultCard(
              count: images.length - previewLimit,
              onTap: onSeeMore,
            );
          }
          return GalleryTile(
            image: images[index],
            heroTag: '$heroPrefix-${images[index].id}-$index',
            sourceImages: images,
            sourceIndex: index,
            heroPrefix: heroPrefix,
          );
        },
      ),
    );
  }
}

class SeeMoreResultCard extends StatelessWidget {
  const SeeMoreResultCard({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF151827).withOpacity(0.74),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFF3D448C).withOpacity(0.6)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.more_horiz_rounded,
                color: Color(0xFFBFC4FF),
                size: 24,
              ),
              const SizedBox(height: 4),
              const Text(
                'See More',
                style: TextStyle(
                  color: Color(0xFFE6E8FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '+$count',
                  style: const TextStyle(
                    color: Color(0xFF8F96B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GalleryGrid extends StatelessWidget {
  const GalleryGrid({
    super.key,
    required this.images,
    required this.topPadding,
    this.bottomPadding = 0,
    this.sourceImages,
    this.heroPrefix = 'gallery-image',
  });

  final List<GalleryImage> images;
  final double topPadding;
  final double bottomPadding;
  final List<GalleryImage>? sourceImages;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    // sourceImages/sourceIndex preserve the ordering that the detail page should
    // swipe through after a tile is opened.
    return SliverPadding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      sliver: SliverGrid.builder(
        itemCount: images.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          final source = sourceImages ?? images;
          final sourceIndex = source.indexWhere(
            (candidate) => candidate.id == images[index].id,
          );
          return GalleryTile(
            image: images[index],
            heroTag:
                '$heroPrefix-${images[index].id}-${sourceIndex < 0 ? index : sourceIndex}',
            sourceImages: source,
            sourceIndex: sourceIndex < 0 ? index : sourceIndex,
            heroPrefix: heroPrefix,
          );
        },
      ),
    );
  }
}

class HomeTopChrome extends StatelessWidget {
  const HomeTopChrome({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.searching,
    required this.onSubmitted,
    required this.onClear,
    required this.onChipSelected,
    required this.showIndexingCard,
    required this.indexingCardCollapsed,
    required this.indexingComplete,
    required this.indexingStored,
    required this.indexingTotal,
    required this.indexingFraction,
    required this.onToggleIndexingCard,
  });

  static double height({
    required bool showIndexingCard,
    required bool indexingCardCollapsed,
  }) {
    return 183 +
        (showIndexingCard
            ? IndexingProgressCard.height(collapsed: indexingCardCollapsed) + 10
            : 0);
  }

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool searching;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final ValueChanged<String> onChipSelected;
  final bool showIndexingCard;
  final bool indexingCardCollapsed;
  final bool indexingComplete;
  final int indexingStored;
  final int indexingTotal;
  final double indexingFraction;
  final VoidCallback onToggleIndexingCard;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF060710),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerLeft,
              child: HomeHeader(),
            ),
          ),
          const SizedBox(height: 20),
          SearchPanel(
            controller: searchController,
            focusNode: searchFocusNode,
            searching: searching,
            onSubmitted: onSubmitted,
            onClear: onClear,
          ),
          const SizedBox(height: 10),
          if (showIndexingCard) ...[
            IndexingProgressCard(
              collapsed: indexingCardCollapsed,
              completed: indexingComplete,
              stored: indexingStored,
              total: indexingTotal,
              fraction: indexingFraction,
              onTap: onToggleIndexingCard,
            ),
            const SizedBox(height: 10),
          ],
          FilterRow(onSelected: onChipSelected),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class SearchTopChrome extends StatelessWidget {
  const SearchTopChrome({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onSubmitted,
    required this.onClear,
    required this.showIndexingCard,
    required this.indexingCardCollapsed,
    required this.indexingComplete,
    required this.indexingStored,
    required this.indexingTotal,
    required this.indexingFraction,
    required this.onToggleIndexingCard,
  });

  static double height({
    required bool showIndexingCard,
    required bool indexingCardCollapsed,
  }) {
    return 74 +
        (showIndexingCard
            ? IndexingProgressCard.height(collapsed: indexingCardCollapsed) + 8
            : 0);
  }

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool showIndexingCard;
  final bool indexingCardCollapsed;
  final bool indexingComplete;
  final int indexingStored;
  final int indexingTotal;
  final double indexingFraction;
  final VoidCallback onToggleIndexingCard;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF060710),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchPanel(
              controller: controller,
              focusNode: focusNode,
              searching: searching,
              onSubmitted: onSubmitted,
              onClear: onClear,
            ),
            if (showIndexingCard) ...[
              const SizedBox(height: 8),
              IndexingProgressCard(
                collapsed: indexingCardCollapsed,
                completed: indexingComplete,
                stored: indexingStored,
                total: indexingTotal,
                fraction: indexingFraction,
                onTap: onToggleIndexingCard,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class IndexingProgressCard extends StatelessWidget {
  const IndexingProgressCard({
    super.key,
    required this.collapsed,
    required this.completed,
    required this.stored,
    required this.total,
    required this.fraction,
    required this.onTap,
  });

  static double height({required bool collapsed}) => collapsed ? 34 : 96;

  final bool collapsed;
  final bool completed;
  final int stored;
  final int total;
  final double fraction;
  final VoidCallback onTap;

  String get _percentLabel {
    if (completed) return '100%';
    if (total <= 0) return 'Scanning';
    return '${(fraction * 100).round().clamp(0, 100)}%';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: height(collapsed: collapsed),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(collapsed ? 999 : 16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFF111424).withOpacity(0.94),
              borderRadius: BorderRadius.circular(collapsed ? 999 : 16),
              border: Border.all(
                color: const Color(0xFF3B438E).withOpacity(0.68),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6871FF).withOpacity(0.10),
                  blurRadius: 18,
                ),
              ],
            ),
            child: ClipRect(
              child: collapsed ? _collapsedContent() : _expandedContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsedContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF8790FF),
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              completed
                  ? 'Indexing complete'
                  : 'Indexing in background • $_percentLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE6E8FF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF9EA5C8),
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _expandedContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF202757),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF9EA6FF),
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  completed
                      ? 'Gallery index complete'
                      : total <= 0
                          ? 'Indexing your gallery'
                          : 'Indexing $stored of $total images',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                _percentLabel,
                style: const TextStyle(
                  color: Color(0xFFBFC4FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Color(0xFF9EA5C8),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Search quality improves as indexing continues.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF9BA1B8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: completed ? 1 : fraction,
              ),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value:
                      total <= 0 && !completed ? null : value.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: const Color(0xFF24283A),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF8790FF),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF1D2356),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6871F1).withOpacity(0.6)),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF8790FF),
            size: 22,
          ), /* const Icon(
            Icons.photo_library_rounded,
            size: 16,
            color: Color(0xFF8D95FF),
          ), */
        ),
        const SizedBox(width: 10),
        const Text(
          'GalleryMind',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        // TO BE IMPLEMENTED:
        /*const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF706CF8), width: 2),
                image: const DecorationImage(
                  image: AssetImage('assets/images/img2.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF17D77C),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF060710), width: 2),
                ),
              ),
            ),
          ],
        ), */
      ],
    );
  }
}

class FixedHeightHeaderDelegate extends SliverPersistentHeaderDelegate {
  FixedHeightHeaderDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant FixedHeightHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}

class SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  SearchHeaderDelegate({
    required this.child,
    required this.topPadding,
    required this.bottomPadding,
  });

  final Widget child;
  final double topPadding;
  final double bottomPadding;

  @override
  double get minExtent => 52 + topPadding + bottomPadding;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: const Color(0xFF060710),
      child: Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SearchHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        topPadding != oldDelegate.topPadding ||
        bottomPadding != oldDelegate.bottomPadding;
  }
}

class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.searching,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final bool searching;
  final VoidCallback onClear;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  bool listening = false;
  bool hasText = false;

  @override
  void initState() {
    super.initState();
    hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    // This local state avoids rebuilding the full HomePage just to show/hide
    // the small X button inside the text field.
    final nextHasText = widget.controller.text.isNotEmpty;
    if (nextHasText != hasText && mounted) {
      setState(() => hasText = nextHasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF111424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF454A8F).withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6871FF).withOpacity(0.18),
            blurRadius: 22,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          /* const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF8790FF),
            size: 22,
          ), */
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Color(0xFFE6E8FF),
                fontSize: 13,
                letterSpacing: 0,
              ),
              decoration: const InputDecoration(
                hintText: 'Search by vibe, memory, or text',
                hintStyle: TextStyle(
                  color: Color(0xFF858AA9),
                  fontSize: 13,
                  letterSpacing: 0,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (hasText)
            IconButton(
              tooltip: 'Clear search',
              onPressed: widget.onClear,
              icon: const Icon(
                Icons.close_rounded,
                color: Color(0xFF9CA4B8),
                size: 19,
              ),
            ),
          GestureDetector(
            onTap: () {
              // With text present, the trailing button submits search. With an
              // empty field, it just toggles the visual "listening" state.
              final query = widget.controller.text.trim();
              if (query.isNotEmpty) {
                widget.onSubmitted(query);
              } else {
                setState(() => listening = !listening);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: listening
                    ? const Color(0xFF323B82)
                    : const Color(0xFF23283A),
                shape: BoxShape.circle,
              ),
              child: widget.searching
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      listening
                          ? Icons.graphic_eq_rounded
                          : Icons.search_rounded,
                      color: listening
                          ? const Color(0xFF9AA1FF)
                          : const Color(0xFF9CA4B8),
                      size: 18,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilterRow extends StatelessWidget {
  const FilterRow({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilterChipPill(
          label: 'Selfies',
          query: 'selfie',
          icon: Icons.camera_alt_rounded,
          onSelected: onSelected,
        ),
        const SizedBox(width: 8),
        FilterChipPill(
          label: 'Screenshots',
          query: 'screenshot',
          icon: Icons.desktop_windows_rounded,
          onSelected: onSelected,
        ),
        const SizedBox(width: 8),
        FilterChipPill(
          label: 'Memes',
          query: 'meme',
          icon: Icons.tag_faces,
          selected: true,
          onSelected: onSelected,
        ),
      ],
    );
  }
}

class FilterChipPill extends StatelessWidget {
  const FilterChipPill({
    super.key,
    required this.label,
    required this.query,
    required this.icon,
    required this.onSelected,
    this.selected = false,
  });

  final String label;
  final String query;
  final IconData icon;
  final ValueChanged<String> onSelected;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelected(query),
        child: Container(
          height: 35,
          decoration: BoxDecoration(
            color: const Color(0xFF171923),
            /* selected ? const Color(0xFF1D2153) : const Color(0xFF171923), */
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: const Color(0xFF2B2E3A),
              /* selected ? const Color(0xFF3D448C) : const Color(0xFF2B2E3A), */
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 10,
                /* selected ? 10 : 13 */
                color: const Color(
                    0xFF8790FF), /* selected
                    ? const Color(0xFF8790FF)
                    : const Color(0xFF80879A), */
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFBFC4FF),
                    /* selected
                        ? const Color(0xFFBFC4FF)
                        : const Color(0xFFBCC0CF), */
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GallerySectionTitle extends StatelessWidget {
  const GallerySectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 3,
          decoration: const BoxDecoration(
            color: Color(0xFF8C95FF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFE8EAFF),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class GalleryTile extends StatefulWidget {
  const GalleryTile({
    super.key,
    required this.image,
    required this.heroTag,
    required this.sourceImages,
    required this.sourceIndex,
    required this.heroPrefix,
  });

  final GalleryImage image;
  final String heroTag;
  final List<GalleryImage> sourceImages;
  final int sourceIndex;
  final String heroPrefix;

  @override
  State<GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<GalleryTile> {
  bool pressed = false;

  void _openDetail() {
    // Pass the whole visible source list to the detail page so the user can
    // swipe left/right through the same ordering they came from.
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageDetailPage(
            image: widget.image,
            heroTag: widget.heroTag,
            images: widget.sourceImages,
            heroTags: List.generate(
              widget.sourceImages.length,
              (index) =>
                  // Hero tags must match the grid tile tags exactly or the
                  // image transition cannot connect both routes.
                  '${widget.heroPrefix}-${widget.sourceImages[index].id}-$index',
            ),
            initialIndex: widget.sourceIndex,
            heroPrefix: widget.heroPrefix,
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
      onTap: _openDetail,
      onTapDown: (_) => setState(() => pressed = true),
      onTapCancel: () => setState(() => pressed = false),
      onTapUp: (_) => setState(() => pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: pressed ? 0.96 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: widget.heroTag,
                child: GalleryImageView(uri: widget.image.assetPath),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
