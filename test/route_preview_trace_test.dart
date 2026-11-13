import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/navigation/domain/geo_point.dart';
import 'package:navi/features/navigation/presentation/route_preview_trace.dart';

void main() {
  test(
    'large decorative traces have bounded projections and retain endpoints',
    () {
      final points = [
        for (var i = 0; i < 20000; i++)
          GeoPoint(6.5 + i / 1000000, 3.3 + math.sin(i / 20) / 1000),
      ];
      final samples = previewProjectionPoints(points);
      expect(samples.length, lessThanOrEqualTo(160));
      expect(samples.first, points.first);
      expect(samples.last, points.last);
      expect(points.length, 20000);
    },
  );
  test(
    'simplification preserves a sparse corner and bounds repeated coordinates',
    () {
      final points = [
        for (var i = 0; i < 1000; i++) GeoPoint(6.5, 3.3 + i / 100000),
        for (var i = 0; i < 1000; i++) GeoPoint(6.5 + i / 100000, 3.30999),
      ];
      final samples = previewProjectionPoints(points, limit: 8);
      expect(samples, contains(points[999]));
      expect(samples.length, lessThanOrEqualTo(8));
      final repeated = List.filled(1000, const GeoPoint(6.5, 3.3));
      expect(previewProjectionPoints(repeated), hasLength(2));
    },
  );
}
