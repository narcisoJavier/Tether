import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether/screens/cyber_logo_data.dart';
import 'package:tether/screens/cyber_splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CyberLogoData', () {
    test('all stroke categories contain valid geometry within unit bounds', () {
      expect(CyberLogoData.terminalBoxStrokes.isNotEmpty, isTrue);
      expect(CyberLogoData.promptStrokes.isNotEmpty, isTrue);
      expect(CyberLogoData.cursorStrokes.isNotEmpty, isTrue);
      expect(CyberLogoData.snakeBodyStrokes.isNotEmpty, isTrue);
      expect(CyberLogoData.snakeHeadStrokes.isNotEmpty, isTrue);
      expect(CyberLogoData.snakeTongueStrokes.isNotEmpty, isTrue);

      final allCategories = [
        CyberLogoData.terminalBoxStrokes,
        CyberLogoData.promptStrokes,
        CyberLogoData.cursorStrokes,
        CyberLogoData.snakeBodyStrokes,
        CyberLogoData.snakeHeadStrokes,
        CyberLogoData.snakeTongueStrokes,
      ];

      for (final cat in allCategories) {
        for (final stroke in cat) {
          expect(stroke.isNotEmpty, isTrue);
          for (final pt in stroke) {
            expect(pt.dx >= 0.0 && pt.dx <= 1.0, isTrue);
            expect(pt.dy >= 0.0 && pt.dy <= 1.0, isTrue);
          }
        }
      }
    });
  });

  group('CyberSplashScreen', () {
    testWidgets('renders squircle container and CustomPaint', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CyberSplashScreen(),
        ),
      );

      expect(find.byType(CyberSplashScreen), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('tap triggers onBootComplete callback immediately', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CyberSplashScreen(
            onBootComplete: () => completed = true,
          ),
        ),
      );

      await tester.tap(find.byType(CyberSplashScreen));
      await tester.pump();

      expect(completed, isTrue);
    });

    testWidgets('completes animation and triggers onBootComplete after 3500ms', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CyberSplashScreen(
            onBootComplete: () => completed = true,
          ),
        ),
      );

      expect(completed, isFalse);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(completed, isFalse);

      await tester.pump(const Duration(milliseconds: 2600));
      expect(completed, isTrue);
    });
  });
}
