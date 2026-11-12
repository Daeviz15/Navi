import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Topographical definition of the word "N A V I" and the traveler's journey across it.
class NaviLetterWalkPainter extends CustomPainter {
  NaviLetterWalkPainter({
    required this.progress,
    this.showGuideline = true,
    this.primaryColor = const Color(0xFFF59E0B),
    this.accentColor = const Color(0xFFFDE68A),
    this.dimColor = const Color(0x1FFFFFFF),
  });

  /// Master progress of the splash sequence: 0.0 -> 1.0
  final double progress;
  final bool showGuideline;
  final Color primaryColor;
  final Color accentColor;
  final Color dimColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2 - 20);

    // Dynamic scale: fits comfortably on small screens down to 320px
    final double targetWidth = math.min(size.width * 0.82, 300.0);
    final double scale = targetWidth / 280.0;
    final double letterH = 68.0 * scale;
    final double letterYTop = center.dy - letterH / 2;
    final double letterYBase = center.dy + letterH / 2;
    final double letterYMid = (letterYTop + letterYBase) / 2;

    // Proportional letter horizontal layout
    // Word: [ N ] (gap) [ A ] (gap) [ V ] (gap) [ I ]
    final double nW = 46.0 * scale;
    final double aW = 50.0 * scale;
    final double vW = 48.0 * scale;
    final double iW = 20.0 * scale;
    final double gap = 20.0 * scale;

    final double totalW = nW + aW + vW + iW + (gap * 3);
    final double startX = center.dx - totalW / 2;

    // Letter anchor coordinates
    // N
    final double nX0 = startX;
    final double nX1 = nX0 + nW;

    // A
    final double aX0 = nX1 + gap;
    final double aXMid = aX0 + aW / 2;
    final double aX1 = aX0 + aW;

    // V
    final double vX0 = aX1 + gap;
    final double vXMid = vX0 + vW / 2;
    final double vX1 = vX0 + vW;

    // I
    final double iX0 = vX1 + gap;
    final double iXMid = iX0 + iW / 2;
    final double iX1 = iX0 + iW;

    // --- 1. Draw Blueprint Guidelines (faint outlines of letters) ---
    if (showGuideline) {
      final guidePaint = Paint()
        ..color = dimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // N outline
      final pN = Path()
        ..moveTo(nX0, letterYBase)
        ..lineTo(nX0, letterYTop)
        ..lineTo(nX1, letterYBase)
        ..lineTo(nX1, letterYTop);
      canvas.drawPath(pN, guidePaint);

      // A outline
      final pA = Path()
        ..moveTo(aX0, letterYBase)
        ..lineTo(aXMid, letterYTop)
        ..lineTo(aX1, letterYBase);
      canvas.drawPath(pA, guidePaint);
      canvas.drawLine(
        Offset(aX0 + (aW * 0.22), letterYMid + (letterH * 0.08)),
        Offset(aX1 - (aW * 0.22), letterYMid + (letterH * 0.08)),
        guidePaint,
      );

      // V outline
      final pV = Path()
        ..moveTo(vX0, letterYTop)
        ..lineTo(vXMid, letterYBase)
        ..lineTo(vX1, letterYTop);
      canvas.drawPath(pV, guidePaint);

      // I outline
      final pI = Path()
        ..moveTo(iXMid, letterYTop)
        ..lineTo(iXMid, letterYBase);
      canvas.drawPath(pI, guidePaint);
      // Top & bottom caps of I
      canvas.drawLine(
        Offset(iX0, letterYTop),
        Offset(iX1, letterYTop),
        guidePaint,
      );
      canvas.drawLine(
        Offset(iX0, letterYBase),
        Offset(iX1, letterYBase),
        guidePaint,
      );
    }

    // --- 2. Calculate Active Letter Drawing Progress & Traveler Position ---
    // Journey Phases:
    // 0.00 -> 0.08: Approach N
    // 0.08 -> 0.16: Ascend N left pillar
    // 0.16 -> 0.28: Walk diagonal of N
    // 0.28 -> 0.36: Ascend N right pillar
    // 0.36 -> 0.42: Leap N -> A
    // 0.42 -> 0.54: Climb A to apex (+ crossbar shoots across)
    // 0.54 -> 0.64: Descend A
    // 0.64 -> 0.70: Leap A -> V
    // 0.70 -> 0.80: Descend into V valley
    // 0.80 -> 0.88: Ascend out of V
    // 0.88 -> 0.92: Leap V -> I
    // 0.92 -> 1.00: Summit on I (stance, radiant pulse shockwave)

    Offset travelerPos = Offset(startX - 30 * scale, letterYBase);
    double travelerSlope = 0.0;
    bool isAirborne = false;
    bool isStanding = false;
    double stridePhase = progress * 40.0 * math.pi;

    // Progress fractions for each letter stroke (0.0 to 1.0)
    double nStroke1 = 0.0; // left pillar
    double nStroke2 = 0.0; // diagonal
    double nStroke3 = 0.0; // right pillar

    double aStroke1 = 0.0; // left leg
    double aCross = 0.0;   // crossbar
    double aStroke2 = 0.0; // right leg

    double vStroke1 = 0.0; // left arm
    double vStroke2 = 0.0; // right arm

    double iCap = 0.0;     // top cap
    double iStem = 0.0;    // vertical stem
    double iBase = 0.0;    // bottom cap

    if (progress < 0.08) {
      final t = progress / 0.08;
      travelerPos = Offset.lerp(
        Offset(startX - 35 * scale, letterYBase),
        Offset(nX0, letterYBase),
        t,
      )!;
      travelerSlope = 0.0;
    } else if (progress < 0.16) {
      final t = (progress - 0.08) / 0.08;
      nStroke1 = t;
      travelerPos = Offset.lerp(
        Offset(nX0, letterYBase),
        Offset(nX0, letterYTop),
        t,
      )!;
      travelerSlope = -math.pi / 2.2; // steep climb
    } else if (progress < 0.28) {
      nStroke1 = 1.0;
      final t = (progress - 0.16) / 0.12;
      nStroke2 = t;
      travelerPos = Offset.lerp(
        Offset(nX0, letterYTop),
        Offset(nX1, letterYBase),
        t,
      )!;
      travelerSlope = math.atan2(letterYBase - letterYTop, nX1 - nX0); // downhill
    } else if (progress < 0.36) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      final t = (progress - 0.28) / 0.08;
      nStroke3 = t;
      travelerPos = Offset.lerp(
        Offset(nX1, letterYBase),
        Offset(nX1, letterYTop),
        t,
      )!;
      travelerSlope = -math.pi / 2.2;
    } else if (progress < 0.42) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      final t = (progress - 0.36) / 0.06;
      isAirborne = true;
      // Parabolic jump from top of N to lower-left of A
      final p0 = Offset(nX1, letterYTop);
      final p1 = Offset(aX0, letterYBase);
      final arcHeight = 18.0 * scale;
      final currentX = p0.dx + (p1.dx - p0.dx) * t;
      final currentY = p0.dy + (p1.dy - p0.dy) * t - 4 * arcHeight * t * (1 - t);
      travelerPos = Offset(currentX, currentY);
      travelerSlope = 0.15;
    } else if (progress < 0.54) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      final t = (progress - 0.42) / 0.12;
      aStroke1 = t;
      if (t > 0.45) {
        aCross = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
      }
      travelerPos = Offset.lerp(
        Offset(aX0, letterYBase),
        Offset(aXMid, letterYTop),
        t,
      )!;
      travelerSlope = math.atan2(letterYTop - letterYBase, aXMid - aX0); // uphill
    } else if (progress < 0.64) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      aStroke1 = 1.0;
      aCross = 1.0;
      final t = (progress - 0.54) / 0.10;
      aStroke2 = t;
      travelerPos = Offset.lerp(
        Offset(aXMid, letterYTop),
        Offset(aX1, letterYBase),
        t,
      )!;
      travelerSlope = math.atan2(letterYBase - letterYTop, aX1 - aXMid); // downhill
    } else if (progress < 0.70) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      aStroke1 = 1.0;
      aCross = 1.0;
      aStroke2 = 1.0;
      final t = (progress - 0.64) / 0.06;
      isAirborne = true;
      // Parabolic jump from bottom of A to top-left of V
      final p0 = Offset(aX1, letterYBase);
      final p1 = Offset(vX0, letterYTop);
      final arcHeight = 22.0 * scale;
      final currentX = p0.dx + (p1.dx - p0.dx) * t;
      final currentY = p0.dy + (p1.dy - p0.dy) * t - 4 * arcHeight * t * (1 - t);
      travelerPos = Offset(currentX, currentY);
      travelerSlope = -0.2;
    } else if (progress < 0.80) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      aStroke1 = 1.0;
      aCross = 1.0;
      aStroke2 = 1.0;
      final t = (progress - 0.70) / 0.10;
      vStroke1 = t;
      travelerPos = Offset.lerp(
        Offset(vX0, letterYTop),
        Offset(vXMid, letterYBase),
        t,
      )!;
      travelerSlope = math.atan2(letterYBase - letterYTop, vXMid - vX0); // downhill
    } else if (progress < 0.88) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      aStroke1 = 1.0;
      aCross = 1.0;
      aStroke2 = 1.0;
      vStroke1 = 1.0;
      final t = (progress - 0.80) / 0.08;
      vStroke2 = t;
      travelerPos = Offset.lerp(
        Offset(vXMid, letterYBase),
        Offset(vX1, letterYTop),
        t,
      )!;
      travelerSlope = math.atan2(letterYTop - letterYBase, vX1 - vXMid); // uphill
    } else if (progress < 0.92) {
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      aStroke1 = 1.0;
      aCross = 1.0;
      aStroke2 = 1.0;
      vStroke1 = 1.0;
      vStroke2 = 1.0;
      final t = (progress - 0.88) / 0.04;
      isAirborne = true;
      // Parabolic jump to the top platform of I
      final p0 = Offset(vX1, letterYTop);
      final p1 = Offset(iXMid, letterYTop);
      final arcHeight = 12.0 * scale;
      final currentX = p0.dx + (p1.dx - p0.dx) * t;
      final currentY = p0.dy + (p1.dy - p0.dy) * t - 4 * arcHeight * t * (1 - t);
      travelerPos = Offset(currentX, currentY);
      travelerSlope = 0.0;
    } else {
      // 0.92 -> 1.00: The Summit on I
      nStroke1 = 1.0;
      nStroke2 = 1.0;
      nStroke3 = 1.0;
      aStroke1 = 1.0;
      aCross = 1.0;
      aStroke2 = 1.0;
      vStroke1 = 1.0;
      vStroke2 = 1.0;
      iCap = 1.0;
      final t = ((progress - 0.92) / 0.06).clamp(0.0, 1.0);
      iStem = t;
      iBase = t;
      travelerPos = Offset(iXMid, letterYTop);
      travelerSlope = 0.0;
      isStanding = true;
    }

    // --- 3. Draw Active Illuminated Strokes ---
    // If summit reached, boost the glow intensity to create a triumphant bloom
    final double bloomBoost = progress >= 0.92
        ? 1.0 + (((progress - 0.92) / 0.08).clamp(0.0, 1.0) * 0.4)
        : 1.0;

    _drawActiveStrokes(
      canvas: canvas,
      scale: scale,
      letterYTop: letterYTop,
      letterYBase: letterYBase,
      letterYMid: letterYMid,
      letterH: letterH,
      nX0: nX0,
      nX1: nX1,
      aX0: aX0,
      aXMid: aXMid,
      aX1: aX1,
      aW: aW,
      vX0: vX0,
      vXMid: vXMid,
      vX1: vX1,
      iX0: iX0,
      iXMid: iXMid,
      iX1: iX1,
      nStroke1: nStroke1,
      nStroke2: nStroke2,
      nStroke3: nStroke3,
      aStroke1: aStroke1,
      aCross: aCross,
      aStroke2: aStroke2,
      vStroke1: vStroke1,
      vStroke2: vStroke2,
      iCap: iCap,
      iStem: iStem,
      iBase: iBase,
      bloomBoost: bloomBoost,
    );

    // --- 4. Radiant Pulse Wave at Summit ---
    if (progress >= 0.93) {
      final pulseT = ((progress - 0.93) / 0.07).clamp(0.0, 1.0);
      final pulseRadius = pulseT * (totalW * 0.75);
      final pulseOpacity = (1.0 - pulseT).clamp(0.0, 1.0) * 0.45;
      final pulsePaint = Paint()
        ..color = primaryColor.withValues(alpha: pulseOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * scale;
      canvas.drawCircle(Offset(iXMid, letterYTop), pulseRadius, pulsePaint);

      // Soft ambient golden bloom centered around word
      final bloomPaint = Paint()
        ..color = primaryColor.withValues(alpha: (0.08 * pulseT).clamp(0.0, 0.08))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawCircle(center, totalW * 0.4, bloomPaint);
    }

    // --- 5. Draw Dynamic Particle Sparks at Traveler's Feet ---
    if (!isStanding) {
      _drawFootfallSparks(canvas, travelerPos, scale, progress);
    }

    // --- 6. Draw Stylized Walking Traveler Rig ---
    _drawTraveler(
      canvas: canvas,
      pos: travelerPos,
      scale: scale,
      slope: travelerSlope,
      stridePhase: stridePhase,
      isAirborne: isAirborne,
      isStanding: isStanding,
      progress: progress,
    );
  }

  void _drawActiveStrokes({
    required Canvas canvas,
    required double scale,
    required double letterYTop,
    required double letterYBase,
    required double letterYMid,
    required double letterH,
    required double nX0,
    required double nX1,
    required double aX0,
    required double aXMid,
    required double aX1,
    required double aW,
    required double vX0,
    required double vXMid,
    required double vX1,
    required double iX0,
    required double iXMid,
    required double iX1,
    required double nStroke1,
    required double nStroke2,
    required double nStroke3,
    required double aStroke1,
    required double aCross,
    required double aStroke2,
    required double vStroke1,
    required double vStroke2,
    required double iCap,
    required double iStem,
    required double iBase,
    double bloomBoost = 1.0,
  }) {
    // Outer glow paint
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: (0.38 * bloomBoost).clamp(0.0, 0.75))
      ..style = PaintingStyle.stroke
      ..strokeWidth = (9.0 * scale) * (bloomBoost > 1.0 ? 1.25 : 1.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        5 * (bloomBoost > 1.0 ? 1.3 : 1.0),
      );

    // Core crisp neon paint
    final corePaint = Paint()
      ..color = Color.lerp(primaryColor, accentColor, ((bloomBoost - 1.0) / 0.4).clamp(0.0, 1.0))!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Helper to draw segment with glow
    void drawSegment(Offset p1, Offset p2, double fraction) {
      if (fraction <= 0.0) return;
      final target = Offset.lerp(p1, p2, fraction)!;
      canvas.drawLine(p1, target, glowPaint);
      canvas.drawLine(p1, target, corePaint);
    }

    // N
    drawSegment(Offset(nX0, letterYBase), Offset(nX0, letterYTop), nStroke1);
    drawSegment(Offset(nX0, letterYTop), Offset(nX1, letterYBase), nStroke2);
    drawSegment(Offset(nX1, letterYBase), Offset(nX1, letterYTop), nStroke3);

    // A
    drawSegment(Offset(aX0, letterYBase), Offset(aXMid, letterYTop), aStroke1);
    drawSegment(Offset(aXMid, letterYTop), Offset(aX1, letterYBase), aStroke2);
    if (aCross > 0.0) {
      final barP1 = Offset(aX0 + (aW * 0.22), letterYMid + (letterH * 0.08));
      final barP2 = Offset(aX1 - (aW * 0.22), letterYMid + (letterH * 0.08));
      drawSegment(barP1, barP2, aCross);
    }

    // V
    drawSegment(Offset(vX0, letterYTop), Offset(vXMid, letterYBase), vStroke1);
    drawSegment(Offset(vXMid, letterYBase), Offset(vX1, letterYTop), vStroke2);

    // I
    if (iCap > 0.0) {
      drawSegment(Offset(iX0, letterYTop), Offset(iX1, letterYTop), iCap);
    }
    drawSegment(Offset(iXMid, letterYTop), Offset(iXMid, letterYBase), iStem);
    if (iBase > 0.0) {
      drawSegment(Offset(iX0, letterYBase), Offset(iX1, letterYBase), iBase);
    }
  }

  void _drawFootfallSparks(Canvas canvas, Offset pos, double scale, double t) {
    final sparkPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final randSeed = (t * 100).toInt();
    for (int i = 0; i < 4; i++) {
      final angle = (randSeed * 37 + i * 89) % 360 * (math.pi / 180);
      final dist = (3.0 + ((randSeed + i * 13) % 7)) * scale;
      final sparkOffset = Offset(
        pos.dx + math.cos(angle) * dist,
        pos.dy + math.sin(angle) * dist * 0.5,
      );
      canvas.drawCircle(sparkOffset, 1.2 * scale, sparkPaint);
    }
  }

  void _drawTraveler({
    required Canvas canvas,
    required Offset pos,
    required double scale,
    required double slope,
    required double stridePhase,
    required bool isAirborne,
    required bool isStanding,
    required double progress,
  }) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    // Dynamic rotation to conform to the terrain slope
    // Damped so steep slopes don't make the character fall over
    final double bodyTilt = isStanding ? 0.0 : slope.clamp(-0.45, 0.45);
    canvas.rotate(bodyTilt);

    // Scale character proportionally
    final s = scale * 1.05;

    // Kinematic parameters
    double hipBob = 0.0;
    double legAngle1 = 0.0;
    double legAngle2 = 0.0;
    double kneeBend1 = 0.0;
    double kneeBend2 = 0.0;
    double armAngle1 = 0.0;
    double armAngle2 = 0.0;

    if (isStanding) {
      // Gentle breathing idle
      final idleBreath = math.sin(progress * 18 * math.pi) * 0.8 * s;
      hipBob = idleBreath;
      legAngle1 = 0.10;
      legAngle2 = -0.10;
      armAngle1 = 0.12;
      armAngle2 = -0.08;
    } else if (isAirborne) {
      // Leaping pose: front leg reaching, back leg trailing
      hipBob = -2.0 * s;
      legAngle1 = 0.55;  // front leg extends
      legAngle2 = -0.45; // back leg trails
      kneeBend1 = 0.20;
      kneeBend2 = 0.60;
      armAngle1 = -0.45; // arms up for balance
      armAngle2 = 0.35;
    } else {
      // Natural walking gait kinematics
      hipBob = -math.sin(stridePhase).abs() * 2.2 * s;
      legAngle1 = math.sin(stridePhase) * 0.45;
      legAngle2 = -math.sin(stridePhase) * 0.45;

      kneeBend1 = math.max(0.0, math.cos(stridePhase)) * 0.60;
      kneeBend2 = math.max(0.0, -math.cos(stridePhase)) * 0.60;

      // Arms swing opposite to legs
      armAngle1 = -math.sin(stridePhase) * 0.38;
      armAngle2 = math.sin(stridePhase) * 0.38;
    }

    final double hipY = -15.0 * s + hipBob;
    final double shoulderY = -27.0 * s + hipBob;
    final double headY = -33.5 * s + hipBob;

    // Body paints
    final farLimbPaint = Paint()
      ..color = const Color(0xFFD97706)
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round;

    final nearLimbPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.4 * s
      ..strokeCap = StrokeCap.round;

    final torsoPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 3.6 * s
      ..strokeCap = StrokeCap.round;

    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final headGlowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final backpackPaint = Paint()
      ..color = const Color(0xFFB45309)
      ..style = PaintingStyle.fill;

    // 1. Draw Far Arm (behind torso)
    _drawArm(
      canvas: canvas,
      shoulder: Offset(-1.0 * s, shoulderY),
      angle: armAngle2,
      length: 10.0 * s,
      paint: farLimbPaint,
    );

    // 2. Draw Far Leg (behind torso)
    _drawLeg(
      canvas: canvas,
      hip: Offset(0, hipY),
      hipAngle: legAngle2,
      kneeBend: kneeBend2,
      thighLen: 7.5 * s,
      shinLen: 8.0 * s,
      paint: farLimbPaint,
    );

    // 3. Draw Traveler Backpack / Satchel
    final bpRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(-3.8 * s, (shoulderY + hipY) / 2),
        width: 4.8 * s,
        height: 8.5 * s,
      ),
      Radius.circular(2.0 * s),
    );
    canvas.drawRRect(bpRect, backpackPaint);

    // 4. Draw Torso (lean slightly forward into direction of travel)
    final double torsoLean = isStanding ? 0.0 : 1.5 * s;
    canvas.drawLine(
      Offset(0, hipY),
      Offset(torsoLean, shoulderY),
      torsoPaint,
    );

    // 5. Draw Near Leg
    _drawLeg(
      canvas: canvas,
      hip: Offset(0, hipY),
      hipAngle: legAngle1,
      kneeBend: kneeBend1,
      thighLen: 7.5 * s,
      shinLen: 8.0 * s,
      paint: nearLimbPaint,
    );

    // 6. Draw Near Arm
    _drawArm(
      canvas: canvas,
      shoulder: Offset(torsoLean, shoulderY),
      angle: armAngle1,
      length: 10.0 * s,
      paint: nearLimbPaint,
    );

    // 7. Draw Head & Visor
    final headCenter = Offset(torsoLean + 0.5 * s, headY);
    canvas.drawCircle(headCenter, 3.8 * s, headGlowPaint);
    canvas.drawCircle(headCenter, 3.4 * s, headPaint);

    // Subtle explorer visor / eye slit
    final visorPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round;
    final visorDir = isStanding ? 1.0 : 1.2;
    canvas.drawLine(
      Offset(headCenter.dx + 0.5 * s, headCenter.dy),
      Offset(headCenter.dx + (2.8 * s * visorDir), headCenter.dy),
      visorPaint,
    );

    canvas.restore();
  }

  void _drawLeg({
    required Canvas canvas,
    required Offset hip,
    required double hipAngle,
    required double kneeBend,
    required double thighLen,
    required double shinLen,
    required Paint paint,
  }) {
    // Thigh vector
    final knee = Offset(
      hip.dx + math.sin(hipAngle) * thighLen,
      hip.dy + math.cos(hipAngle) * thighLen,
    );
    canvas.drawLine(hip, knee, paint);

    // Shin vector (knee bend applied)
    final totalShinAngle = hipAngle - kneeBend;
    final foot = Offset(
      knee.dx + math.sin(totalShinAngle) * shinLen,
      knee.dy + math.cos(totalShinAngle) * shinLen,
    );
    canvas.drawLine(knee, foot, paint);
  }

  void _drawArm({
    required Canvas canvas,
    required Offset shoulder,
    required double angle,
    required double length,
    required Paint paint,
  }) {
    final hand = Offset(
      shoulder.dx + math.sin(angle) * length,
      shoulder.dy + math.cos(angle) * length,
    );
    canvas.drawLine(shoulder, hand, paint);
  }

  @override
  bool shouldRepaint(covariant NaviLetterWalkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.showGuideline != showGuideline ||
        oldDelegate.primaryColor != primaryColor;
  }
}
