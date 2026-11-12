import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/core/theme/navi_theme.dart';
import 'package:navi/core/widgets/navi_companion.dart';
import 'package:navi/features/character/presentation/companion_controller.dart';

void main() {
  testWidgets('verify procedural cloud stage bounds across activities', (
    tester,
  ) async {
    for (final activity in CompanionActivity.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: NaviTheme.dark,
          home: Scaffold(
            body: Center(
              child: NaviCompanion(
                size: 290,
                activity: activity,
                holdPose: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stageRect = tester.getRect(find.byKey(const ValueKey('navi-stage')));
      final canvasRect = tester.getRect(
        find.byKey(const ValueKey('navi-cloud-canvas')),
      );
      expect(stageRect.width, 290);
      expect(stageRect.height, 290);
      expect(canvasRect.left, greaterThanOrEqualTo(stageRect.left + 16));
      expect(canvasRect.right, lessThanOrEqualTo(stageRect.right - 16));
      expect(canvasRect.top, greaterThanOrEqualTo(stageRect.top + 20));
      expect(canvasRect.bottom, lessThanOrEqualTo(stageRect.bottom - 20));
    }
  });
}
