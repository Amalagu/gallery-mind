import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/aura_bottom_nav.dart';
import '../services/gallery_preferences.dart';
import 'albums_page.dart';
import 'home_page.dart';
import 'settings_page.dart';

// GalleryShell owns the main tab layout and the small set of preferences that
// need to be shared across Home, Albums, Settings, and Image Detail routes.
class GalleryShell extends StatefulWidget {
  const GalleryShell({super.key});

  @override
  State<GalleryShell> createState() => _GalleryShellState();
}

class _GalleryShellState extends State<GalleryShell> {
  // The key lets the shell ask HomePage whether it wants to consume the Android
  // back button first, for example to collapse search results.
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final GlobalKey<AlbumsPageState> _albumsKey = GlobalKey<AlbumsPageState>();
  final GalleryPreferences _preferences = GalleryPreferences();
  int selectedIndex = 1;
  int _similarityThreshold = GalleryPreferences.defaultSimilarityThreshold;
  bool _showFilenameMatches = GalleryPreferences.defaultShowFilenameMatches;
  DateTime? _lastBackPressedAt;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final threshold = await _preferences.getSimilarityThreshold();
    final showFilenameMatches = await _preferences.getShowFilenameMatches();
    if (!mounted) return;
    setState(() {
      _similarityThreshold = threshold;
      _showFilenameMatches = showFilenameMatches;
    });
  }

  Future<void> _setSimilarityThreshold(int value) async {
    setState(() => _similarityThreshold = value);
    await _preferences.setSimilarityThreshold(value);
  }

  Future<void> _setShowFilenameMatches(bool value) async {
    setState(() => _showFilenameMatches = value);
    await _preferences.setShowFilenameMatches(value);
  }

  Future<void> _handleBack() async {
    // If the user is not on Home, back simply returns to the center Home tab.
    if (selectedIndex != 1) {
      setState(() => selectedIndex = 1);
      return;
    }

    final homeConsumedBack = await _homeKey.currentState?.handleSystemBack();
    if (homeConsumedBack ?? false) return;

    // Once Home has nothing to close, require a second back press within two
    // seconds before exiting the app.
    final now = DateTime.now();
    final shouldExit = _lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) < const Duration(seconds: 2);
    if (shouldExit) {
      await SystemNavigator.pop();
      return;
    }

    _lastBackPressedAt = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to quit GalleryMind'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each tab alive. That prevents Home from restarting its
    // background indexing check every time the user visits Albums or Settings.
    final pages = <Widget>[
      AlbumsPage(
        key: _albumsKey,
        similarityThreshold: _similarityThreshold,
      ),
      HomePage(
        key: _homeKey,
        similarityThreshold: _similarityThreshold,
        showFilenameMatches: _showFilenameMatches,
      ),
      SettingsPage(
        key: const ValueKey('settings'),
        similarityThreshold: _similarityThreshold,
        showFilenameMatches: _showFilenameMatches,
        onSimilarityThresholdChanged: _setSimilarityThreshold,
        onShowFilenameMatchesChanged: _setShowFilenameMatches,
      ),
    ];

    return PopScope<void>(
      // Android back is fully handled by _handleBack so the app can show the
      // "press again to quit" Snackbar instead of closing immediately.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF060710),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Stack(
                children: [
                  IndexedStack(
                    index: selectedIndex,
                    children: pages,
                  ),
                  Positioned(
                    left: 34,
                    right: 34,
                    bottom: 16,
                    child: AuraBottomNav(
                      selectedIndex: selectedIndex,
                      onSelected: (index) {
                        if (index == 1 && selectedIndex == 1) {
                          _homeKey.currentState?.resetToInitialHome();
                          return;
                        }
                        setState(() => selectedIndex = index);
                        if (index == 0) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _albumsKey.currentState?.reloadFavorites();
                          });
                        }
                        if (index == 1) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _homeKey.currentState?.resetToInitialHome();
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
