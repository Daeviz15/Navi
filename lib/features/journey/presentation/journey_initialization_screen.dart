import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/navi_page.dart';
import '../../location/application/location_controller.dart';
import 'journey_controller.dart';

class JourneyInitializationScreen extends ConsumerStatefulWidget {
  const JourneyInitializationScreen({super.key});

  static const introDuration = Duration(milliseconds: 2300);

  @override
  ConsumerState<JourneyInitializationScreen> createState() =>
      _JourneyInitializationScreenState();
}

class _JourneyInitializationScreenState
    extends ConsumerState<JourneyInitializationScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drive;
  late final Animation<double> _progress;
  bool _begun = false;
  bool _introFinished = false;
  bool _permissionInFlight = false;
  bool _locationStepDone = false;
  bool _foreground = true;

  bool get _isCurrent =>
      mounted &&
      GoRouter.of(context).routeInformationProvider.value.uri.path ==
          '/initialize';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drive = AnimationController(
      vsync: this,
      duration: JourneyInitializationScreen.introDuration,
    )..addStatusListener(_onAnimationStatus);
    _progress = _drive.drive(CurveTween(curve: Curves.easeInOutCubic));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_begun) return;
    _begun = true;
    final reduced = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(journeyDraftProvider).destination.isEmpty) {
        return;
      }
      if (reduced) {
        _drive.value = 1;
      } else if (_foreground) {
        unawaited(_drive.forward());
      }
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _introFinished = true);
    unawaited(_advance());
  }

  Future<void> _advance() async {
    if (!_isCurrent || !_foreground || !_introFinished || _permissionInFlight) {
      return;
    }
    if (!_locationStepDone) {
      _permissionInFlight = true;
      // enable checks existing permission first. It returns after acquisition
      // starts, not after a GPS fix: a weak signal must not trap this screen.
      await ref.read(locationControllerProvider.notifier).enable();
      _permissionInFlight = false;
      if (!_isCurrent) return;
      _locationStepDone = true;
    }
    if (mounted && _foreground) context.go('/preview');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _drive.stop();
    } else if (_introFinished) {
      unawaited(_advance());
    } else if (_begun) {
      unawaited(_drive.forward());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drive.removeStatusListener(_onAnimationStatus);
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(journeyDraftProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (draft.destination.isEmpty) {
      return NaviPage(
        title: 'Getting ready',
        child: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Choose a destination first'),
          ),
        ),
      );
    }
    final hasChecklist = draft.checklist.isNotEmpty && !draft.isCasual;
    return NaviPage(
      title: 'Getting ready',
      onBack: () => context.go('/'),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A LITTLE MOMENT, THEN WE GO.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  draft.destination,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                if (draft.purposeSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    draft.purposeSummary,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 26),
                RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('journey-bus-orbit'),
                    foregroundPainter: _BusOrbitPainter(
                      progress: _progress,
                      gold: scheme.primary,
                      road: scheme.outlineVariant,
                      ink: scheme.onPrimary,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Container(
                        key: const ValueKey('initialization-essentials'),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              hasChecklist
                                  ? Icons.checklist_rounded
                                  : Icons.explore_outlined,
                              size: 24,
                              color: scheme.primary,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              hasChecklist
                                  ? 'Your essentials'
                                  : 'Travel light.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            if (hasChecklist)
                              for (final item in draft.checklist)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        draft.checkedItems.contains(item)
                                            ? Icons.check_circle_rounded
                                            : Icons
                                                  .radio_button_unchecked_rounded,
                                        size: 16,
                                        color: draft.checkedItems.contains(item)
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          item,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                            else
                              Text(
                                'Your destination is noted.\nLet’s find our starting point.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  child: Text(
                    _introFinished
                        ? 'Finding our starting point…'
                        : 'Your plans. My company.',
                    key: ValueKey(_introFinished),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single continuous top-down bus lap; no video, image assets or rebuild loop.
class _BusOrbitPainter extends CustomPainter {
  _BusOrbitPainter({
    required this.progress,
    required this.gold,
    required this.road,
    required this.ink,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color gold;
  final Color road;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(14);
    final radius = math.min(28.0, rect.shortestSide / 3);
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcToPoint(
        Offset(rect.right, rect.top + radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.right, rect.bottom - radius)
      ..arcToPoint(
        Offset(rect.right - radius, rect.bottom),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.left + radius, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.bottom - radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.left, rect.top + radius)
      ..arcToPoint(
        Offset(rect.left + radius, rect.top),
        radius: Radius.circular(radius),
      )
      ..close();
    final metric = path.computeMetrics().first;
    final base = Paint()
      ..color = road
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (double at = 0; at < metric.length; at += 12) {
      canvas.drawPath(
        metric.extractPath(at, math.min(at + 4, metric.length)),
        base,
      );
    }
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress.value),
      Paint()
        ..color = gold.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final tangent = metric.getTangentForOffset(
      (metric.length * progress.value).clamp(0, metric.length - 0.001),
    )!;
    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    canvas.rotate(tangent.angle);
    // Axles, body, windows and lamps remain crisp in both themes.
    final tyre = Paint()..color = ink;
    for (final x in [-8.0, 8.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, 0), width: 4, height: 21),
          const Radius.circular(2),
        ),
        tyre,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-17, -9, 34, 18),
        const Radius.circular(5),
      ),
      Paint()..color = gold,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, -6, 4, 12),
        const Radius.circular(1.5),
      ),
      tyre,
    );
    for (double x = -12; x < 5; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, -6, 3, 3), tyre);
      canvas.drawRect(Rect.fromLTWH(x, 3, 3, 3), tyre);
    }
    canvas.drawCircle(const Offset(15, -5), 1.3, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(15, 5), 1.3, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BusOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.gold != gold ||
      oldDelegate.road != road ||
      oldDelegate.ink != ink;
}
