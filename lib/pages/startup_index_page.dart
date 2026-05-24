import 'package:flutter/material.dart';

import '../services/embedding_index.dart';
import 'gallery_shell.dart';

// This is the first real screen after MaterialApp starts. It decides whether
// to show onboarding, ask for photo permission, run indexing, or enter the app.
class StartupIndexPage extends StatefulWidget {
  const StartupIndexPage({super.key});

  @override
  State<StartupIndexPage> createState() => _StartupIndexPageState();
}

class _StartupIndexPageState extends State<StartupIndexPage> {
  // EmbeddingIndex is the Dart wrapper around the native Android ONNX/indexing
  // code. All permission, onboarding, and gallery indexing calls pass through it.
  final EmbeddingIndex _index = EmbeddingIndex();
  final PageController _pageController = PageController();

  // These values drive the loading/indexing UI shown before the gallery opens.
  IndexProgress? _progress;
  GalleryIndexSummary? _summary;
  String _status = 'Preparing GalleryMind';

  // These booleans form the startup state machine.
  bool _checkingOnboarding = true;
  bool _showOnboarding = false;
  bool _permissionDenied = false;
  bool _indexingFailed = false;
  bool _bootstrapping = false;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepare();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      // Onboarding is stored natively so the user only sees it after install.
      final completed = await _index.hasCompletedOnboarding();
      if (!mounted) return;
      if (completed) {
        setState(() => _checkingOnboarding = false);
        await _bootstrap();
      } else {
        setState(() {
          _checkingOnboarding = false;
          _showOnboarding = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingOnboarding = false);
      await _bootstrap();
    }
  }

  Future<void> _finishOnboarding({bool requestPermission = true}) async {
    // Mark onboarding done before bootstrapping so future launches skip it.
    await _index.completeOnboarding();
    if (!mounted) return;
    setState(() {
      _showOnboarding = false;
      _permissionDenied = false;
    });
    await _bootstrap(requestPermission: requestPermission);
  }

  Future<void> _bootstrap({bool requestPermission = true}) async {
    if (_bootstrapping) return;
    setState(() {
      _bootstrapping = true;
      _indexingFailed = false;
      _status = 'Checking photo access';
    });

    try {
      // Android permission prompts must be triggered from native code. If the
      // user says no, we stop here and show the "Allow Photos" retry state.
      final hasPermission = await _index.hasPhotoPermission();
      final granted = hasPermission ||
          (requestPermission && await _index.requestPhotoPermission());

      if (!mounted) return;
      if (!granted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const GalleryShell()),
        );
        return;
      }

      setState(() {
        _permissionDenied = false;
        _status = 'Preparing your recent images';
      });
      // Only index a small newest-first batch before opening the app. The Home
      // screen continues the remaining gallery work in the background.
      final summary = await _index.indexNewGalleryImages(
        limit: 100,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _status = progress.total == 0
                ? 'Gallery index is up to date'
                : 'Indexing recent image ${progress.completed} of ${progress.total}';
          });
        },
      );

      if (!mounted) return;
      if (summary.indexed == 0 && summary.failed > 0) {
        setState(() {
          _summary = summary;
          _indexingFailed = true;
          _bootstrapping = false;
          _status =
              'GalleryMind could not index the first images. Please retry after checking photo access.';
        });
        return;
      }
      setState(() {
        _summary = summary;
        _status = summary.indexed == 0 && summary.failed == 0
            ? 'Gallery index is up to date'
            : 'Ready with ${summary.stored} indexed images';
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const GalleryShell()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _indexingFailed = true;
        _bootstrapping = false;
        _status = 'Indexing paused: $error';
      });
    }
  }

  void _nextOnboardingPage() {
    // The final onboarding page is the permission page, so its primary button
    // finishes onboarding and asks Android for photo access.
    if (_pageIndex >= 2) {
      _finishOnboarding(requestPermission: _pageIndex == 2);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingOnboarding) {
      return const Scaffold(
        backgroundColor: Color(0xFF060710),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF060710),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _showOnboarding
                ? _OnboardingFlow(
                    controller: _pageController,
                    pageIndex: _pageIndex,
                    onPageChanged: (index) =>
                        setState(() => _pageIndex = index),
                    onPrimary: _nextOnboardingPage,
                    onMaybeLater: () =>
                        _finishOnboarding(requestPermission: false),
                  )
                : _IndexingView(
                    progress: _progress,
                    summary: _summary,
                    status: _status,
                    permissionDenied: _permissionDenied,
                    indexingFailed: _indexingFailed,
                    onAllowPhotos: () => _bootstrap(),
                    onRetry: () => _bootstrap(),
                    onOpen: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const GalleryShell(),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingFlow extends StatelessWidget {
  const _OnboardingFlow({
    required this.controller,
    required this.pageIndex,
    required this.onPageChanged,
    required this.onPrimary,
    required this.onMaybeLater,
  });

  final PageController controller;
  final int pageIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onPrimary;
  final VoidCallback onMaybeLater;

  @override
  Widget build(BuildContext context) {
    // These data objects keep the onboarding copy/icons separate from the
    // reusable page layout below.
    final pages = [
      const _OnboardingPageData(
        icon: Icons.image_rounded,
        title: 'GalleryMind',
        label: 'Semantic Search',
        body:
            'Search by mood, description, or objects. Aura understands the context of your images.',
        badge: Icons.near_me_rounded,
      ),
      const _OnboardingPageData(
        icon: Icons.memory_rounded,
        title: 'Your photos never leave your device.',
        label: 'PRIVACY FIRST',
        body:
            'Our CLIP AI models run entirely on your phone. No cloud, no tracking, just intelligence.',
        badge: Icons.security_rounded,
      ),
      const _OnboardingPageData(
        icon: Icons.photo_library_rounded,
        title: 'Grant Access',
        label: 'LOCAL INDEXING',
        body:
            'To begin indexing your library and enabling semantic search, GalleryMind needs access to your photos.',
        badge: Icons.lock_rounded,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: controller,
              onPageChanged: onPageChanged,
              itemCount: pages.length,
              itemBuilder: (context, index) =>
                  _OnboardingPage(data: pages[index]),
            ),
          ),
          _PageDots(count: pages.length, index: pageIndex),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7D86F7),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Text(
                pageIndex == 0
                    ? 'Get Started'
                    : pageIndex == 1
                        ? 'Continue'
                        : 'Allow Access',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (pageIndex == 2) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onMaybeLater,
              child: const Text('Maybe Later'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.label,
    required this.body,
    required this.badge,
  });

  final IconData icon;
  final String title;
  final String label;
  final String body;
  final IconData badge;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF090A18), Color(0xFF05060D), Color(0xFF0B1022)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _OnboardingGlowPainter()),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A5E).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(22),
                    border:
                        Border.all(color: const Color(0xFF8D95FF), width: 2),
                  ),
                  child:
                      Icon(data.icon, color: const Color(0xFF9CA4FF), size: 34),
                ),
                const SizedBox(height: 30),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161635).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF494E9F)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(data.badge,
                          color: const Color(0xFF8D95FF), size: 13),
                      const SizedBox(width: 7),
                      Text(
                        data.label,
                        style: const TextStyle(
                          color: Color(0xFFDADFFF),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  data.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  data.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB5BAD1),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    letterSpacing: 0,
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

class _IndexingView extends StatelessWidget {
  const _IndexingView({
    required this.progress,
    required this.summary,
    required this.status,
    required this.permissionDenied,
    required this.indexingFailed,
    required this.onAllowPhotos,
    required this.onRetry,
    required this.onOpen,
  });

  final IndexProgress? progress;
  final GalleryIndexSummary? summary;
  final String status;
  final bool permissionDenied;
  final bool indexingFailed;
  final VoidCallback onAllowPhotos;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // A null fraction means native indexing has not reported a total yet, so
    // the progress indicator stays indeterminate.
    final fraction = progress?.fraction;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 8,
                    backgroundColor: const Color(0xFF171923),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF8790FF),
                    ),
                  ),
                ),
                Text(
                  fraction == null ? 'AI' : '${(fraction * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Text(
            permissionDenied
                ? 'Photo Access Needed'
                : 'Building your Private Visual Index',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFAEB4CA),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              height: 1.35,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 18),
            Text(
              '${summary!.stored} images stored locally',
              style: const TextStyle(
                color: Color(0xFF8790FF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
          if (permissionDenied) ...[
            const SizedBox(height: 24),
            // This button retries permission/indexing. It disappears as soon
            // as permission is granted because permissionDenied becomes false.
            FilledButton(
              onPressed: onAllowPhotos,
              child: const Text('Allow Photos'),
            ),
          ],
          if (indexingFailed) ...[
            const SizedBox(height: 24),
            FilledButton(
                onPressed: onRetry, child: const Text('Retry Indexing')),
            const SizedBox(height: 10),
            TextButton(
                onPressed: onOpen, child: const Text('Open GalleryMind')),
          ],
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (dotIndex) {
        final active = dotIndex == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: active ? 24 : 7,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8790FF) : const Color(0xFF2C3145),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _OnboardingGlowPainter extends CustomPainter {
  // Lightweight custom paint used only for the soft onboarding background glow.
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2635A8).withOpacity(0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.5, size.height * 0.38),
        radius: size.width * 0.72,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.38),
      size.width * 0.72,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
