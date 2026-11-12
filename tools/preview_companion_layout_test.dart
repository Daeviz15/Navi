import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/core/theme/navi_theme.dart';
import 'package:navi/core/widgets/navi_companion.dart';
import 'package:navi/features/character/domain/navi_clip.dart';
import 'package:navi/features/character/presentation/companion_controller.dart';
import 'package:navi/features/home/presentation/home_screen.dart';

class _PreviewBehavior extends CompanionController {
  _PreviewBehavior(this.frame);
  final CompanionFrame frame;
  @override
  CompanionFrame build() {
    super.build();
    return frame;
  }
}

void main() {
  testWidgets('render idle, attention and compact layout previews', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() async {
      final syne = FontLoader('Syne')
        ..addFont(rootBundle.load('assets/fonts/Syne-Variable.ttf'));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([syne.load(), icons.load()]);
    });
    final output = Directory('build/companion-previews');
    await tester.runAsync(() => output.create(recursive: true));
    for (final preview in [
      (name: 'dark-idle', light: false, focused: false, narrow: false),
      (name: 'dark-attention', light: false, focused: true, narrow: false),
      (name: 'light-attention', light: true, focused: true, narrow: false),
      (name: 'compact-attention', light: false, focused: true, narrow: true),
    ]) {
      tester.view.physicalSize = preview.narrow
          ? const Size(320, 568)
          : const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = preview.narrow
          ? 1.5
          : 1;
      final boundary = GlobalKey();
      final clip = preview.focused ? NaviClips.listening : NaviClips.sip;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            companionProvider.overrideWith(
              () => _PreviewBehavior(
                CompanionFrame(
                  preview.focused
                      ? CompanionActivity.listening
                      : CompanionActivity.idle,
                  clip,
                  0,
                  still: true,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: preview.light ? NaviTheme.light : NaviTheme.dark,
            home: MediaQuery(
              data: MediaQueryData.fromView(tester.view).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(preview.narrow ? 1.5 : 1),
              ),
              child: RepaintBoundary(key: boundary, child: const HomeScreen()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      if (preview.narrow) {
        await tester.ensureVisible(find.byType(NaviCompanion));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File(
            '${output.path}/${preview.name}.png',
          ).writeAsBytes(data.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
