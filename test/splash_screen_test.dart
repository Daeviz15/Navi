import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/splash/presentation/navi_letter_walk_painter.dart';
import 'package:navi/features/splash/presentation/splash_screen.dart';

void main() {
  group('NaviLetterWalkPainter', () {
    test('renders without error at all milestone progress points', () {
      final milestones = [0.0, 0.05, 0.12, 0.22, 0.33, 0.40, 0.50, 0.60, 0.75, 0.85, 0.94, 1.0];
      const size = Size(360, 240);

      for (final p in milestones) {
        final painter = NaviLetterWalkPainter(progress: p);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, size);
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      }
    });

    test('shouldRepaint returns true when progress changes', () {
      final painter1 = NaviLetterWalkPainter(progress: 0.1);
      final painter2 = NaviLetterWalkPainter(progress: 0.2);
      expect(painter2.shouldRepaint(painter1), isTrue);
    });

    test('shouldRepaint returns false when properties are identical', () {
      final painter1 = NaviLetterWalkPainter(progress: 0.5);
      final painter2 = NaviLetterWalkPainter(progress: 0.5);
      expect(painter2.shouldRepaint(painter1), isFalse);
    });
  });

  group('SplashScreen Widget', () {
    testWidgets('renders CustomPaint with letter walk painter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            duration: Duration(milliseconds: 1000),
            autoNavigate: false,
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('SKIP'), findsOneWidget);

      // Advance animation halfway
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CustomPaint), findsWidgets);

      // Advance to near end where subtitle appears
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('YOUR PURPOSE-AWARE COMPANION'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('tapping SKIP triggers on-tap handler without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            duration: Duration(milliseconds: 2000),
            autoNavigate: false,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 400));
      final skipBtn = find.text('SKIP');
      expect(skipBtn, findsOneWidget);
      await tester.tap(skipBtn);
      await tester.pump();
    });
  });
}
