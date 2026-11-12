import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/character/domain/navi_clip.dart';
import '../../features/character/presentation/companion_controller.dart';
import '../theme/navi_theme.dart';

/// A procedural, real-time audio-reactive volumetric cloud stage.
///
/// Riverpod owns high-level [CompanionActivity] state; this widget owns its
/// animation tickers and listens directly to [audioLevel] during paint so
/// 60 fps voice modulation never rebuilds the surrounding widget tree.
class NaviCompanion extends StatefulWidget {
  const NaviCompanion({
    super.key,
    this.size = 290,
    this.clip = NaviClips.sip,
    this.activity,
    this.repeat = false,
    this.revision = 0,
    this.engaged = false,
    this.holdPose = true,
    this.audioLevel,
    this.onCompleted,
    this.onTap,
  });

  static const transitionDuration = Duration(milliseconds: 240);
  static const focusDuration = Duration(milliseconds: 440);
  static const cycleDuration = Duration(milliseconds: 2400);

  final double size;
  final NaviClip clip;
  final CompanionActivity? activity;
  final bool repeat;
  final int revision;
  final bool engaged;
  final bool holdPose;
  final ValueListenable<double>? audioLevel;
  final VoidCallback? onCompleted;
  final VoidCallback? onTap;

  CompanionActivity get resolvedActivity {
    if (activity != null) return activity!;
    if (clip == NaviClips.listening) return CompanionActivity.listening;
    if (clip == NaviClips.thinking) return CompanionActivity.thinking;
    if (clip == NaviClips.speaking) return CompanionActivity.speaking;
    if (clip == NaviClips.sideEye || clip == NaviClips.smile) {
      return CompanionActivity.reaction;
    }
    return CompanionActivity.idle;
  }

  @override
  State<NaviCompanion> createState() => NaviCompanionState();
}

class NaviCompanionState extends State<NaviCompanion>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final AnimationController _blend;
  late final CurvedAnimation _blendCurve;
  late final AnimationController _cycle;
  late _CloudPose _fromPose;
  late _CloudPose _toPose;
  int _activeRevision = 0;
  bool _foreground = true;
  bool _visible = true;
  bool _reduceMotion = false;

  bool get _canAnimate => _foreground && _visible && !_reduceMotion;

  /// Exposed for deterministic widget verification.
  bool get isAnimating => _blend.isAnimating || _cycle.isAnimating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeRevision = widget.revision;
    _fromPose = _CloudPose.forActivity(
      widget.resolvedActivity,
      still: widget.holdPose,
    );
    _toPose = _fromPose;
    _blend = AnimationController(
      vsync: this,
      duration: NaviCompanion.transitionDuration,
      value: 1.0,
    );
    _blendCurve = CurvedAnimation(
      parent: _blend,
      curve: Curves.easeInOutCubic,
    );
    _cycle = AnimationController(
      vsync: this,
      duration: NaviCompanion.cycleDuration,
    )..addStatusListener(_onCycleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(NaviCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextActivity = widget.resolvedActivity;
    final nextPose = _CloudPose.forActivity(
      nextActivity,
      still: widget.holdPose,
    );
    final changed =
        widget.revision != _activeRevision ||
        nextActivity != oldWidget.resolvedActivity ||
        widget.holdPose != oldWidget.holdPose ||
        widget.repeat != oldWidget.repeat;

    if (changed) {
      _activeRevision = widget.revision;
      _fromPose = _CloudPose.lerp(_fromPose, _toPose, _blendCurve.value);
      _toPose = nextPose;
      if (_canAnimate) {
        unawaited(_blend.forward(from: 0));
      } else {
        _blend.value = 1.0;
      }
      _cycle.stop();
      _cycle.reset();
    }
    _syncAnimation();
  }

  void _syncAnimation() {
    if (!_canAnimate) {
      if (_blend.isAnimating) _blend.value = 1.0;
      if (_cycle.isAnimating) _cycle.stop();
      return;
    }
    if (widget.holdPose) {
      if (_cycle.isAnimating) _cycle.stop();
      return;
    }
    if (widget.repeat) {
      if (!_cycle.isAnimating) {
        unawaited(_cycle.repeat());
      }
    } else if (!_cycle.isAnimating && _cycle.value < 1.0) {
      unawaited(_cycle.forward());
    }
  }

  void _onCycleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (widget.repeat || widget.holdPose) return;
    final completedRevision = _activeRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _activeRevision == completedRevision &&
          !widget.repeat &&
          !widget.holdPose) {
        widget.onCompleted?.call();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncAnimation();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cycle.removeStatusListener(_onCycleStatus);
    _blendCurve.dispose();
    _blend.dispose();
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final repaint = Listenable.merge([
      _blend,
      _cycle,
      if (widget.audioLevel != null) widget.audioLevel!,
    ]);

    return Semantics(
      label: widget.clip.description,
      image: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: RepaintBoundary(
          child: AnimatedContainer(
            key: const ValueKey('navi-stage'),
            duration: _reduceMotion
                ? Duration.zero
                : NaviCompanion.focusDuration,
            curve: Curves.easeInOutCubic,
            width: widget.size,
            height: widget.size,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: AnimatedScale(
              key: const ValueKey('navi-focus'),
              scale: widget.engaged && !_reduceMotion ? 1.035 : 1,
              alignment: Alignment.bottomCenter,
              duration: _reduceMotion
                  ? Duration.zero
                  : NaviCompanion.focusDuration,
              curve: Curves.easeInOutCubic,
              child: TickerMode(
                enabled: _foreground && _visible,
                child: CustomPaint(
                  key: const ValueKey('navi-cloud-canvas'),
                  painter: _NaviCloudPainter(
                    repaint: repaint,
                    blend: _blendCurve,
                    cycle: _cycle,
                    fromPose: _fromPose,
                    toPose: _toPose,
                    activity: widget.resolvedActivity,
                    audioLevel: widget.audioLevel,
                    lightMode: light,
                    reduceMotion: _reduceMotion,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _CloudPose {
  const _CloudPose({
    required this.scaleX,
    required this.scaleY,
    required this.turbulence,
    required this.warmth,
    required this.elevation,
    required this.ringIntensity,
    required this.swirlSpeed,
  });

  final double scaleX;
  final double scaleY;
  final double turbulence;
  final double warmth;
  final double elevation;
  final double ringIntensity;
  final double swirlSpeed;

  static _CloudPose forActivity(
    CompanionActivity activity, {
    required bool still,
  }) => switch (activity) {
    CompanionActivity.idle => _CloudPose(
      scaleX: 1.0,
      scaleY: 1.0,
      turbulence: still ? 0.018 : 0.065,
      warmth: still ? 0.22 : 0.38,
      elevation: 0.0,
      ringIntensity: still ? 0.0 : 0.25,
      swirlSpeed: still ? 0.0 : 1.0,
    ),
    CompanionActivity.reaction => const _CloudPose(
      scaleX: 1.05,
      scaleY: 1.04,
      turbulence: 0.11,
      warmth: 0.62,
      elevation: -0.025,
      ringIntensity: 0.65,
      swirlSpeed: 1.5,
    ),
    CompanionActivity.listening => const _CloudPose(
      scaleX: 0.94,
      scaleY: 0.98,
      turbulence: 0.045,
      warmth: 0.52,
      elevation: -0.03,
      ringIntensity: 0.55,
      swirlSpeed: 1.0,
    ),
    CompanionActivity.thinking => const _CloudPose(
      scaleX: 0.91,
      scaleY: 0.95,
      turbulence: 0.085,
      warmth: 0.85,
      elevation: -0.02,
      ringIntensity: 0.45,
      swirlSpeed: 2.0,
    ),
    CompanionActivity.speaking => const _CloudPose(
      scaleX: 1.04,
      scaleY: 1.03,
      turbulence: 0.125,
      warmth: 0.92,
      elevation: -0.025,
      ringIntensity: 0.78,
      swirlSpeed: 1.5,
    ),
  };

  static _CloudPose lerp(_CloudPose a, _CloudPose b, double t) => _CloudPose(
    scaleX: a.scaleX + (b.scaleX - a.scaleX) * t,
    scaleY: a.scaleY + (b.scaleY - a.scaleY) * t,
    turbulence: a.turbulence + (b.turbulence - a.turbulence) * t,
    warmth: a.warmth + (b.warmth - a.warmth) * t,
    elevation: a.elevation + (b.elevation - a.elevation) * t,
    ringIntensity: a.ringIntensity + (b.ringIntensity - a.ringIntensity) * t,
    swirlSpeed: a.swirlSpeed + (b.swirlSpeed - a.swirlSpeed) * t,
  );
}

class _CloudLobeSpec {
  const _CloudLobeSpec(this.dx, this.dy, this.radius, this.phaseOffset);
  final double dx;
  final double dy;
  final double radius;
  final double phaseOffset;
}

class _NaviCloudPainter extends CustomPainter {
  _NaviCloudPainter({
    required Listenable repaint,
    required this.blend,
    required this.cycle,
    required this.fromPose,
    required this.toPose,
    required this.activity,
    required this.audioLevel,
    required this.lightMode,
    required this.reduceMotion,
  }) : super(repaint: repaint);

  final Animation<double> blend;
  final Animation<double> cycle;
  final _CloudPose fromPose;
  final _CloudPose toPose;
  final CompanionActivity activity;
  final ValueListenable<double>? audioLevel;
  final bool lightMode;
  final bool reduceMotion;

  // Seven sculptural billows forming a balanced, mature cumulus silhouette.
  static const _lobes = <_CloudLobeSpec>[
    _CloudLobeSpec(-0.48, 0.14, 0.34, 0.0), // Left base billow
    _CloudLobeSpec(0.48, 0.15, 0.33, 1.1), // Right base billow
    _CloudLobeSpec(-0.27, -0.15, 0.39, 2.2), // Upper-left shoulder
    _CloudLobeSpec(0.28, -0.12, 0.37, 3.4), // Upper-right shoulder
    _CloudLobeSpec(0.0, -0.26, 0.44, 4.5), // Central crown dome
    _CloudLobeSpec(-0.14, 0.18, 0.38, 5.2), // Inner-left belly
    _CloudLobeSpec(0.16, 0.18, 0.38, 0.7), // Inner-right belly
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final pose = _CloudPose.lerp(fromPose, toPose, blend.value);
    final rawMicLevel = reduceMotion
        ? 0.0
        : (audioLevel?.value ?? 0.0).clamp(0.0, 1.0);
    final phase = reduceMotion ? 0.0 : cycle.value * 2 * math.pi;

    // Synthesize natural speech-cadence envelope during speaking; use live
    // microphone amplitude during listening/armed states.
    final double speechCadence;
    if (!reduceMotion && activity == CompanionActivity.speaking) {
      final syllableA = math.pow(math.sin(phase * 3.0), 2).toDouble();
      final syllableB = math.pow(math.sin(phase * 5.0 + 0.9), 2).toDouble();
      speechCadence = 0.35 + 0.65 * (syllableA * 0.6 + syllableB * 0.4);
    } else if (!reduceMotion && activity == CompanionActivity.reaction) {
      speechCadence = math.sin(cycle.value * math.pi) * 0.75;
    } else {
      speechCadence = 0.0;
    }

    final acousticEnergy = math.max(rawMicLevel, speechCadence).clamp(0.0, 1.0);
    final effectiveTurbulence = reduceMotion
        ? 0.012
        : pose.turbulence + acousticEnergy * 0.16;
    final effectiveWarmth = (pose.warmth + acousticEnergy * 0.35).clamp(
      0.0,
      1.0,
    );

    final shortest = size.shortestSide;
    final unit = shortest * 0.42;
    final center = Offset(
      size.width * 0.5,
      size.height * (0.52 + pose.elevation - acousticEnergy * 0.015),
    );

    // 1. Ambient atmospheric halo behind the cloud.
    _paintAmbientHalo(canvas, center, unit, effectiveWarmth, acousticEnergy);

    // 2. Acoustic resonance wave rings when listening, speaking, or reacting.
    final ringStrength = reduceMotion
        ? 0.0
        : (pose.ringIntensity * 0.45 + acousticEnergy * 0.85).clamp(0.0, 1.0);
    if (ringStrength > 0.04) {
      _paintResonanceRings(
        canvas,
        center,
        unit,
        pose,
        phase,
        ringStrength,
        acousticEnergy,
      );
    }

    // 3. Soft ground shadow beneath the cloud for spatial grounding.
    _paintGroundShadow(canvas, center, unit, pose, acousticEnergy);

    // 4. Unified volumetric cloud contour & 3D internal billowing lobes.
    _paintVolumetricCloud(
      canvas,
      center,
      unit,
      pose,
      phase,
      effectiveTurbulence,
      effectiveWarmth,
      acousticEnergy,
    );
  }

  void _paintAmbientHalo(
    Canvas canvas,
    Offset center,
    double unit,
    double warmth,
    double acousticEnergy,
  ) {
    final haloRadius = unit * (1.28 + acousticEnergy * 0.18);
    final goldColor = lightMode ? NaviColors.goldInk : NaviColors.gold;
    final baseMist = lightMode
        ? const Color(0xFFE5DEC9)
        : const Color(0xFF2A2922);
    final innerColor = Color.lerp(
      baseMist,
      goldColor,
      warmth * 0.75,
    )!.withValues(alpha: lightMode ? 0.28 + warmth * 0.16 : 0.22 + warmth * 0.24);

    final rect = Rect.fromCircle(center: center, radius: haloRadius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          innerColor,
          innerColor.withValues(alpha: innerColor.a * 0.35),
          innerColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.15, 0.82);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(center, haloRadius, paint);
    canvas.restore();
  }

  void _paintResonanceRings(
    Canvas canvas,
    Offset center,
    double unit,
    _CloudPose pose,
    double phase,
    double ringStrength,
    double acousticEnergy,
  ) {
    final accent = lightMode ? NaviColors.goldInk : NaviColors.gold;
    for (var i = 0; i < 2; i++) {
      final waveProgress = reduceMotion
          ? (i + 1) * 0.35
          : ((phase / (2 * math.pi) + i * 0.5) % 1.0);
      final expansion =
          1.02 + waveProgress * (0.22 + acousticEnergy * 0.18);
      final alpha =
          (1.0 - waveProgress) * ringStrength * (lightMode ? 0.28 : 0.36);
      if (alpha <= 0.01) continue;

      final ringPath = _buildCloudContourPath(
        center: center,
        unit: unit * expansion,
        scaleX: pose.scaleX * 1.04,
        scaleY: pose.scaleY * 0.96,
        phase: phase + i * 1.3,
        turbulence: 0.025 + acousticEnergy * 0.06,
      );
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 + (1.0 - waveProgress) * 1.2
        ..color = accent.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawPath(ringPath, ringPaint);
    }
  }

  void _paintGroundShadow(
    Canvas canvas,
    Offset center,
    double unit,
    _CloudPose pose,
    double acousticEnergy,
  ) {
    final shadowCenter = center.translate(0, unit * 0.56);
    final shadowWidth = unit * 1.32 * pose.scaleX * (1.0 - acousticEnergy * 0.05);
    final shadowHeight = unit * 0.22;
    final shadowRect = Rect.fromCenter(
      center: shadowCenter,
      width: shadowWidth,
      height: shadowHeight,
    );
    final shadowColor = lightMode
        ? NaviColors.ink.withValues(alpha: 0.09)
        : NaviColors.gold.withValues(alpha: 0.08);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [shadowColor, shadowColor.withValues(alpha: 0.0)],
      ).createShader(shadowRect);
    canvas.drawOval(shadowRect, paint);
  }

  void _paintVolumetricCloud(
    Canvas canvas,
    Offset center,
    double unit,
    _CloudPose pose,
    double phase,
    double turbulence,
    double warmth,
    double acousticEnergy,
  ) {
    final contour = _buildCloudContourPath(
      center: center,
      unit: unit,
      scaleX: pose.scaleX * (1.0 + acousticEnergy * 0.06),
      scaleY: pose.scaleY * (1.0 + acousticEnergy * 0.08),
      phase: phase,
      turbulence: turbulence,
    );

    final bounds = Rect.fromCircle(center: center, radius: unit * 1.15);

    // Base volumetric body fill with 3D top-lit atmospheric shading.
    final topColor = lightMode
        ? const Color(0xFFFFFFFF)
        : const Color(0xFFF8F6F0);
    final midColor = lightMode
        ? const Color(0xFFECE8DC)
        : const Color(0xFFD8D5CA);
    final baseShadow = lightMode
        ? const Color(0xFFC9C4B4)
        : const Color(0xFF5E5E55);

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, midColor, baseShadow],
        stops: const [0.08, 0.62, 1.0],
      ).createShader(bounds);

    canvas.drawPath(contour, bodyPaint);

    // Clip to the cloud silhouette to sculpt internal 3D billowing puffs
    // and the living golden core luminescence.
    canvas.save();
    canvas.clipPath(contour);

    for (var i = 0; i < _lobes.length; i++) {
      final lobe = _lobes[i];
      final angle = phase * pose.swirlSpeed + lobe.phaseOffset;
      final driftX = reduceMotion
          ? 0.0
          : math.sin(angle) * unit * (0.03 + turbulence * 0.45);
      final driftY = reduceMotion
          ? 0.0
          : math.cos(angle * 1.25) * unit * (0.035 + turbulence * 0.55) -
                acousticEnergy * unit * 0.04 * math.sin(phase * 2 + i);
      final lobeCenter = Offset(
        center.dx + lobe.dx * unit * pose.scaleX + driftX,
        center.dy + lobe.dy * unit * pose.scaleY + driftY,
      );
      final lobeRadius =
          lobe.radius *
          unit *
          (1.0 +
              (reduceMotion
                  ? 0.0
                  : math.sin(angle + i) * (0.03 + acousticEnergy * 0.08)));

      final highlightOffset = lobeCenter.translate(
        -lobeRadius * 0.24,
        -lobeRadius * 0.28,
      );
      final puffHighlight = lightMode
          ? const Color(0xFFFFFFFF)
          : const Color(0xFFFFFEFA);
      final puffMid = Color.lerp(
        lightMode ? const Color(0xFFF3EFE4) : const Color(0xFFE2DFD5),
        NaviColors.gold,
        warmth * 0.18,
      )!;
      final puffShadow = lightMode
          ? const Color(0xFFD5D0C0).withValues(alpha: 0.0)
          : const Color(0xFF45453C).withValues(alpha: 0.0);

      final puffRect = Rect.fromCircle(center: lobeCenter, radius: lobeRadius);
      final puffPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (highlightOffset.dx - lobeCenter.dx) / lobeRadius,
            (highlightOffset.dy - lobeCenter.dy) / lobeRadius,
          ),
          radius: 0.95,
          colors: [
            puffHighlight.withValues(alpha: 0.92),
            puffMid.withValues(alpha: 0.55),
            puffShadow,
          ],
          stops: const [0.0, 0.56, 1.0],
        ).createShader(puffRect);

      canvas.drawCircle(lobeCenter, lobeRadius, puffPaint);
    }

    // Inner living core luminescence (pulses with warmth and voice energy).
    final coreOrbitX = reduceMotion
        ? 0.0
        : math.cos(phase * 2.0) * unit * 0.08 * pose.swirlSpeed * 0.5;
    final coreOrbitY = reduceMotion
        ? 0.0
        : math.sin(phase * 2.0) * unit * 0.05 * pose.swirlSpeed * 0.5;
    final coreCenter = center.translate(coreOrbitX, unit * 0.02 + coreOrbitY);
    final coreRadius = unit * (0.52 + acousticEnergy * 0.22);
    final coreRect = Rect.fromCircle(center: coreCenter, radius: coreRadius);
    final coreAlpha = (0.14 + warmth * 0.34 + acousticEnergy * 0.24).clamp(
      0.0,
      0.72,
    );
    final corePaint = Paint()
      ..blendMode = BlendMode.srcATop
      ..shader = RadialGradient(
        colors: [
          NaviColors.gold.withValues(alpha: coreAlpha),
          NaviColors.gold.withValues(alpha: coreAlpha * 0.35),
          NaviColors.gold.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(coreRect);
    canvas.drawCircle(coreCenter, coreRadius, corePaint);

    canvas.restore();

    // Crisp specular rim along the upper crown so the cloud reads cleanly in
    // both midnight dark mode and warm pearl light mode.
    final rimColor = Color.lerp(
      lightMode ? NaviColors.inkMuted : NaviColors.cloud,
      NaviColors.gold,
      warmth * 0.65,
    )!;
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          rimColor.withValues(alpha: lightMode ? 0.42 : 0.68),
          rimColor.withValues(alpha: lightMode ? 0.16 : 0.22),
          rimColor.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(bounds);

    canvas.drawPath(contour, rimPaint);
  }

  /// Generates a C1-continuous closed cubic spline along the union boundary of
  /// the cloud's structural billows, modulated by multi-octave harmonic waves.
  Path _buildCloudContourPath({
    required Offset center,
    required double unit,
    required double scaleX,
    required double scaleY,
    required double phase,
    required double turbulence,
  }) {
    const sampleCount = 48;
    final points = List<Offset>.generate(sampleCount, (index) {
      final theta = (index / sampleCount) * 2 * math.pi;
      final cosT = math.cos(theta);
      final sinT = math.sin(theta);

      // Base cumulus envelope: wider cushioned horizontal span, gently
      // flattened underside, and three sculpted upper cumulus domes.
      final domeCrown = sinT < 0
          ? 0.16 * math.pow(-sinT, 1.4) * (0.65 + 0.35 * math.cos(theta * 3.0))
          : -0.08 * math.pow(sinT, 1.6);

      // Multi-octave harmonic wave displacement for organic life & speech ripple.
      final wave1 = math.sin(theta * 3.0 + phase) * 0.45;
      final wave2 = math.cos(theta * 5.0 - phase * 2.0) * 0.35;
      final wave3 = math.sin(theta * 7.0 + phase * 3.0) * 0.20;
      final displacement = (wave1 + wave2 + wave3) * turbulence;

      final rx = unit * scaleX * (0.86 + domeCrown * 0.35 + displacement);
      final ry = unit * scaleY * (0.56 + domeCrown + displacement * 0.85);

      return Offset(center.dx + cosT * rx, center.dy + sinT * ry);
    });

    final path = Path();
    for (var i = 0; i < sampleCount; i++) {
      final p0 = points[(i - 1 + sampleCount) % sampleCount];
      final p1 = points[i];
      final p2 = points[(i + 1) % sampleCount];
      final p3 = points[(i + 2) % sampleCount];

      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      }
      // Catmull-Rom to cubic Bézier conversion (tension = 1/6).
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _NaviCloudPainter oldDelegate) =>
      oldDelegate.fromPose != fromPose ||
      oldDelegate.toPose != toPose ||
      oldDelegate.activity != activity ||
      oldDelegate.audioLevel != audioLevel ||
      oldDelegate.lightMode != lightMode ||
      oldDelegate.reduceMotion != reduceMotion;
}
