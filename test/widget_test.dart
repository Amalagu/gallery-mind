import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerymind/pages/gallery_shell.dart';
import 'package:gallerymind/pages/home_page.dart';

void main() {
  const channel = MethodChannel('gallerymind/clip');

  Widget buildTestApp() {
    return const MaterialApp(home: GalleryShell());
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getAllIndexedImages':
          return <Object?>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('renders the GalleryMind home screen', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.text('Aura'), findsOneWidget);
    expect(find.text('Search by vibe, memory, or text'), findsOneWidget);
    expect(find.text('Dec 24, 2023'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('opens the image detail page from a gallery tile',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    await tester.tap(find.byType(GalleryTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Dark Companion Portrait'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Add to'), findsOneWidget);
    expect(find.text('Secure'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('semantic match opens as the current detail page',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    await tester.tap(find.byType(GalleryTile).first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.text('Dark Companion Portrait'),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    final orangeMatch = find.byKey(const ValueKey('semantic-match-orange-car'));
    await tester.ensureVisible(orangeMatch);
    await tester.tap(orangeMatch);
    await tester.pumpAndSettle();

    expect(find.text('Orange Road Machine'), findsOneWidget);
    expect(
      find.text(
        '"A cinematic sports car shot on open asphalt under dramatic sunset clouds."',
      ),
      findsOneWidget,
    );
    expect(find.text('Dark Companion Portrait'), findsNothing);
  });
}
