import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/aura_bottom_nav.dart';
import 'home_page.dart';
import 'placeholder_page.dart';

// GalleryShell owns the main tab layout. The Home page is the center tab, while
// Albums and Settings are placeholders until those screens are built out.
class GalleryShell extends StatefulWidget {
  const GalleryShell({super.key});

  @override
  State<GalleryShell> createState() => _GalleryShellState();
}

class _GalleryShellState extends State<GalleryShell> {
  // The key lets the shell ask HomePage whether it wants to consume the Android
  // back button first, for example to collapse search results.
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  int selectedIndex = 1;
  DateTime? _lastBackPressedAt;

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
    // Each tab is kept simple here; AnimatedSwitcher gives a soft transition
    // when the selected tab changes.
    final pages = <Widget>[
      const PlaceholderPage(
        key: ValueKey('albums'),
        icon: Icons.photo_album_rounded,
        title: 'Albums',
        subtitle: 'Collections screen coming next.',
      ),
      HomePage(key: _homeKey),
      const PlaceholderPage(
        key: ValueKey('settings'),
        icon: Icons.settings_rounded,
        title: 'Settings',
        subtitle: 'Preferences and model controls will live here.',
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: pages[selectedIndex],
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
