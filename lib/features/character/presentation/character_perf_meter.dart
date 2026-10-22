// Archived character experiment. Retained for reference; not part of the active app.
// The home screen now uses the prerecorded Navi video preview.
//
// import 'dart:async';
// import 'dart:collection';
//
// import 'package:flutter/foundation.dart';
// import 'package:flutter/scheduler.dart';
//
// class CharacterPerfMeter extends ChangeNotifier {
//   CharacterPerfMeter({required String initialVariant})
//     : _variant = initialVariant {
//     SchedulerBinding.instance.addTimingsCallback(_onFlutterTimings);
//     _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
//       if (!_disposed) notifyListeners();
//     });
//     _startModelLoad();
//   }
//
//   final Stopwatch _clock = Stopwatch()..start();
//   final Map<String, _ModelMeasurements> _byModel = {};
//   final Queue<_UiFrameSample> _uiFrames = Queue<_UiFrameSample>();
//   Timer? _ticker;
//   Stopwatch? _loadClock;
//   String _variant;
//   bool _disposed = false;
//   bool _dragging = false;
//   int _dragStartedUs = 0;
//   int? _lastEventUs;
//   int _moveEvents = 0;
//   int _longGaps = 0;
//   int _maxGapUs = 0;
//   int _totalGapUs = 0;
//   int _gapCount = 0;
//   int _flutterFramesWhileDragging = 0;
//   final List<double> _buildMs = <double>[];
//   final List<double> _rasterMs = <double>[];
//
//   String get variant => _variant;
//   _ModelMeasurements get _current =>
//       _byModel.putIfAbsent(_variant, () => _ModelMeasurements());
//
//   void changeModel(String name) {
//     if (_dragging) endDrag();
//     _variant = name;
//     _uiFrames.clear();
//     _startModelLoad();
//     notifyListeners();
//   }
//
//   void _startModelLoad() {
//     _loadClock?.stop();
//     _loadClock = Stopwatch()..start();
//     _current.loading = true;
//   }
//
//   void modelLoaded() {
//     final watch = _loadClock;
//     if (watch == null || !watch.isRunning) return;
//     watch.stop();
//     _current
//       ..loadMs = watch.elapsedMilliseconds
//       ..loading = false;
//     notifyListeners();
//   }
//
//   void modelFailed() {
//     _loadClock?.stop();
//     _current.loading = false;
//     notifyListeners();
//   }
//
//   void beginDrag() {
//     _dragging = true;
//     _dragStartedUs = _clock.elapsedMicroseconds;
//     _lastEventUs = null;
//     _moveEvents = 0;
//     _longGaps = 0;
//     _maxGapUs = 0;
//     _totalGapUs = 0;
//     _gapCount = 0;
//     _flutterFramesWhileDragging = 0;
//     _buildMs.clear();
//     _rasterMs.clear();
//     notifyListeners();
//   }
//
//   void pointerMoved() {
//     if (!_dragging) return;
//     final now = _clock.elapsedMicroseconds;
//     final previous = _lastEventUs;
//     _moveEvents += 1;
//     if (previous != null) {
//       final interval = now - previous;
//       if (interval > 0) {
//         _maxGapUs = interval > _maxGapUs ? interval : _maxGapUs;
//         _totalGapUs += interval;
//         _gapCount += 1;
//         if (interval > 33000) _longGaps += 1;
//       }
//     }
//     _lastEventUs = now;
//   }
//
//   void endDrag() {
//     if (!_dragging) return;
//     _dragging = false;
//     final elapsedUs = _clock.elapsedMicroseconds - _dragStartedUs;
//     // Ignore very short accidental drags to keep comparisons useful.
//     if (elapsedUs >= 250000 && _moveEvents >= 3) {
//       final report = _DragMeasurement(
//         seconds: elapsedUs / 1000000.0,
//         moves: _moveEvents,
//         meanGapMs: _gapCount == 0 ? null : _totalGapUs / _gapCount / 1000,
//         worstGapMs: _gapCount == 0 ? null : _maxGapUs / 1000,
//         gapsAbove33Ms: _longGaps,
//         flutterFrames: _flutterFramesWhileDragging,
//         p95BuildMs: _p95(_buildMs),
//         p95RasterMs: _p95(_rasterMs),
//       );
//       _current.drags.add(report);
//       // Keep only a few tests per model to minimize memory usage.
//       if (_current.drags.length > 8) _current.drags.removeAt(0);
//     }
//     notifyListeners();
//   }
//
//   void _onFlutterTimings(List<FrameTiming> frames) {
//     if (_disposed) return;
//     final now = _clock.elapsedMilliseconds;
//     for (final frame in frames) {
//       _uiFrames.add(
//         _UiFrameSample(
//           whenMs: now,
//           buildMs: frame.buildDuration.inMicroseconds / 1000,
//           rasterMs: frame.rasterDuration.inMicroseconds / 1000,
//         ),
//       );
//       if (_dragging) {
//         _flutterFramesWhileDragging++;
//         _buildMs.add(frame.buildDuration.inMicroseconds / 1000);
//         _rasterMs.add(frame.rasterDuration.inMicroseconds / 1000);
//       }
//     }
//     while (_uiFrames.isNotEmpty && now - _uiFrames.first.whenMs > 2500) {
//       _uiFrames.removeFirst();
//     }
//   }
//
//   static double? _p95(List<double> values) {
//     if (values.isEmpty) return null;
//     final sorted = List<double>.of(values)..sort();
//     final index = ((sorted.length - 1) * .95).ceil();
//     return sorted[index];
//   }
//
//   static String _ms(double? ms) =>
//       ms == null ? '–' : '${ms.toStringAsFixed(1)} ms';
//
//   String get loadTimeLabel {
//     if (_current.loading) return 'Loading…';
//     final ms = _current.loadMs;
//     return ms == null ? 'Unavailable' : '$ms ms';
//   }
//
//   bool get isDragging => _dragging;
//
//   String get observedFlutterFramesLabel {
//     // This is merely the number of Flutter frames reported by the engine
//     // over ~2.5 seconds, NOT the WebView's 3D frame rate.
//     final now = _clock.elapsedMilliseconds;
//     final recent = _uiFrames.where((s) => now - s.whenMs <= 2000).toList();
//     if (recent.length < 2) return 'No recent UI frames';
//     return '~${(recent.length / 2).toStringAsFixed(0)}/s (UI only)';
//   }
//
//   String get flutterBuildLabel {
//     final now = _clock.elapsedMilliseconds;
//     final frames = _uiFrames
//         .where((s) => now - s.whenMs <= 2000)
//         .map((s) => s.buildMs)
//         .toList();
//     return _ms(_p95(frames));
//   }
//
//   String get flutterRasterLabel {
//     final now = _clock.elapsedMilliseconds;
//     final frames = _uiFrames
//         .where((s) => now - s.whenMs <= 2000)
//         .map((s) => s.rasterMs)
//         .toList();
//     return _ms(_p95(frames));
//   }
//
//   String get latestGestureLabel {
//     final samples = _current.drags;
//     if (_dragging) return 'Recording rotation…';
//     if (samples.isEmpty) return 'No completed rotation';
//     final last = samples.last;
//     return '${last.seconds.toStringAsFixed(1)}s · '
//         '${(last.moves / last.seconds).toStringAsFixed(0)} touch events/s';
//   }
//
//   String get gestureGapLabel {
//     final samples = _current.drags;
//     if (samples.isEmpty) return '–';
//     final last = samples.last;
//     return '${_ms(last.meanGapMs)} average / ${_ms(last.worstGapMs)} worst';
//   }
//
//   String get delayedInputsLabel {
//     final samples = _current.drags;
//     if (samples.isEmpty) return '–';
//     return '${samples.last.gapsAbove33Ms} gaps over 33 ms';
//   }
//
//   int get dragCount => _current.drags.length;
//
//   void clearCurrentResults() {
//     if (_dragging) endDrag();
//     _current.drags.clear();
//     notifyListeners();
//   }
//
//   String buildReport() {
//     final lines = <String>[
//       'NAVI Character Lab — performance diagnostics',
//       'Note: Flutter frame timings exclude the WebGL 3D drawing loop.',
//       'Touch event frequency is NOT WebGL FPS.',
//       'Device/build: TECNO KI7 (please confirm) / profile recommended',
//       'Models tested: ${_byModel.length}',
//       '',
//     ];
//     const order = <String>[
//       'UV-safe 52K',
//       'UV-safe 68K',
//       'Original 227K',
//       'Motion demo',
//     ];
//     for (final name in order) {
//       final model = _byModel[name];
//       if (model == null) continue;
//       lines.add('$name: load ${model.loadMs ?? 'unknown'} ms');
//       if (model.drags.isEmpty) {
//         lines.add('  No completed drag test');
//       } else {
//         for (var i = 0; i < model.drags.length; i++) {
//           final drag = model.drags[i];
//           lines.add(
//             '  Drag ${i + 1}: ${drag.seconds.toStringAsFixed(2)} s; '
//             '${drag.moves} pointer updates; '
//             '${(drag.moves / drag.seconds).toStringAsFixed(1)} events/s; '
//             'mean gap ${_ms(drag.meanGapMs)}; '
//             'worst gap ${_ms(drag.worstGapMs)}; '
//             'gaps >33ms ${drag.gapsAbove33Ms}; '
//             'Flutter frames during drag ${drag.flutterFrames}; '
//             'Flutter p95 build ${_ms(drag.p95BuildMs)}, '
//             'raster ${_ms(drag.p95RasterMs)}',
//           );
//         }
//       }
//       lines.add('');
//     }
//     return lines.join('\n');
//   }
//
//   @override
//   void dispose() {
//     _disposed = true;
//     _ticker?.cancel();
//     _loadClock?.stop();
//     SchedulerBinding.instance.removeTimingsCallback(_onFlutterTimings);
//     super.dispose();
//   }
// }
//
// class _ModelMeasurements {
//   int? loadMs;
//   bool loading = false;
//   final List<_DragMeasurement> drags = [];
// }
//
// class _DragMeasurement {
//   const _DragMeasurement({
//     required this.seconds,
//     required this.moves,
//     required this.meanGapMs,
//     required this.worstGapMs,
//     required this.gapsAbove33Ms,
//     required this.flutterFrames,
//     required this.p95BuildMs,
//     required this.p95RasterMs,
//   });
//   final double seconds;
//   final int moves;
//   final double? meanGapMs;
//   final double? worstGapMs;
//   final int gapsAbove33Ms;
//   final int flutterFrames;
//   final double? p95BuildMs;
//   final double? p95RasterMs;
// }
//
// class _UiFrameSample {
//   const _UiFrameSample({
//     required this.whenMs,
//     required this.buildMs,
//     required this.rasterMs,
//   });
//   final int whenMs;
//   final double buildMs;
//   final double rasterMs;
// }
