import 'package:flutter/material.dart';

import 'pages/startup_index_page.dart';

// This is the root widget for the whole app. It defines the global app theme
// and chooses the first screen the user sees after launch.
class GalleryMindApp extends StatelessWidget {
  const GalleryMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GalleryMind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // A single dark theme keeps all pages visually consistent.
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7B83FF),
          secondary: Color(0xFF68E4FF),
          surface: Color(0xFF090A12),
          onSurface: Color(0xFFF5F4FF),
        ),
        scaffoldBackgroundColor: const Color(0xFF060710),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      // StartupIndexPage handles first-run onboarding, permission checks,
      // and indexing new gallery photos before showing the main app shell.
      home: const StartupIndexPage(),
    );
  }
}
