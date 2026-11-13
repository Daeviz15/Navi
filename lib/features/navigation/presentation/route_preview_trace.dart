import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../domain/geo_point.dart';

/// Simplifies only the decorative trace. The native road path and domain
/// matching retain the complete provider geometry. Endpoints are preserved.
List<GeoPoint> previewProjectionPoints(
  List<GeoPoint> points, {
  int limit = 160,
}) {
  assert(limit >= 2);
  if (points.length <= limit) return points;
  if (points.length > 2048) {
    // Bound simplification work on large provider responses. Each bucket keeps
    // its strongest bend as well as its endpoint, rather than dropping corners
    // with a uniform stride. The full native route is never simplified.
    final stride = ((points.length - 1) / 1023).ceil();
    final reduced = <GeoPoint>[points.first];
    for (var start = 0; start < points.length - 1; start += stride) {
      final end = math.min(start + stride, points.length - 1);
      final a = Offset(points[start].longitude, points[start].latitude);
      final b = Offset(points[end].longitude, points[end].latitude);
      final delta = b - a;
      var farthest = 0.0, bend = -1;
      for (var i = start + 1; i < end; i++) {
        final p = Offset(points[i].longitude, points[i].latitude);
        final t = delta.distanceSquared == 0
            ? 0.0
            : ((p - a).dx * delta.dx + (p - a).dy * delta.dy) /
                  delta.distanceSquared;
        final distance = (p - (a + delta * t.clamp(0.0, 1.0))).distanceSquared;
        if (distance > farthest) {
          farthest = distance;
          bend = i;
        }
      }
      if (bend >= 0) reduced.add(points[bend]);
      reduced.add(points[end]);
    }
    points = reduced;
  }
  final scale = math.cos(points.first.latitude * math.pi / 180);
  final planar = [
    for (final p in points) Offset(p.longitude * scale, p.latitude),
  ];
  var span = 0.0;
  for (final p in planar) {
    span = math.max(span, (p - planar.first).distance);
  }
  var tolerance = math.max(span / 4096, 1e-9);
  while (true) {
    final keep = <int>{0, points.length - 1};
    final work = <(int, int)>[(0, points.length - 1)];
    while (work.isNotEmpty) {
      final (start, end) = work.removeLast();
      final a = planar[start], delta = planar[end] - a;
      var farthest = tolerance * tolerance, found = -1;
      for (var i = start + 1; i < end; i++) {
        final t = delta.distanceSquared == 0
            ? 0.0
            : ((planar[i] - a).dx * delta.dx + (planar[i] - a).dy * delta.dy) /
                  delta.distanceSquared;
        final distance =
            (planar[i] - (a + delta * t.clamp(0.0, 1.0))).distanceSquared;
        if (distance > farthest) {
          farthest = distance;
          found = i;
        }
      }
      if (found >= 0) {
        keep.add(found);
        work.addAll([(start, found), (found, end)]);
      }
    }
    if (keep.length <= limit) {
      final indices = keep.toList()..sort();
      return List.unmodifiable([for (final i in indices) points[i]]);
    }
    tolerance *= 2;
  }
}

/// Native projection runs once after camera settling. Frames repaint only this
/// canvas; they do not rebuild GoogleMap or transmit polylines over its channel.
class RoutePreviewTrace extends CustomPainter {
  RoutePreviewTrace({
    required this.path,
    required this.phase,
    required this.gold,
  }) : metric = path.computeMetrics().firstOrNull,
       super(repaint: phase);
  final Path path;
  final PathMetric? metric;
  final Animation<double> phase;
  final Color gold;
  static const blue = Color(0xFF65B5FF);

  @override
  void paint(Canvas canvas, Size size) {
    final route = metric;
    if (route == null || route.length < 2) return;
    canvas.save();
    // Reserve the native attribution strip. No custom painting covers it.
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width, math.max(0, size.height - 32)),
    );
    for (var i = 0; i < 2; i++) {
      final colour = i == 0 ? gold : blue;
      final head = (phase.value + i * .5) % 1;
      final end = head * route.length;
      final start = math.max(0.0, end - math.min(60, route.length * .18));
      final trail = route.extractPath(start, end);
      canvas.drawPath(
        trail,
        Paint()
          ..color = colour.withValues(alpha: .16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        trail,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      final tangent = route.getTangentForOffset(end);
      if (tangent == null) continue;
      canvas.save();
      canvas.translate(tangent.position.dx, tangent.position.dy);
      canvas.rotate(math.atan2(tangent.vector.dy, tangent.vector.dx));
      final arrow = Path()
        ..moveTo(6, 0)
        ..lineTo(-3, -4)
        ..lineTo(-1, 0)
        ..lineTo(-3, 4)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()
          ..color = const Color(0xFF111215)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(arrow, Paint()..color = const Color(0xFFFFF7DC));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RoutePreviewTrace oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.phase != phase ||
      oldDelegate.gold != gold;
}
