// Archived character experiment. Retained for reference; not part of the active app.
// The home screen now uses the prerecorded Navi video preview.
//
// import 'dart:convert';
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// // Diagnostic-only: the public Flutter3DViewer API does not expose its WebView.
// // ModelViewer is the viewer used internally by flutter_3d_controller 2.3.0.
// // This import is intentionally isolated so production can stay on the public API.
// import 'package:flutter_3d_controller/src/core/modules/model_viewer/model_viewer.dart';
//
// enum _QualityMode { native, adaptive, aggressive }
//
// extension _QualityModeDetails on _QualityMode {
//   String get label => switch (this) {
//         _QualityMode.native => 'Full',
//         _QualityMode.adaptive => 'Adaptive',
//         _QualityMode.aggressive => 'Adaptive low',
//       };
//
//   double get minimumScale => switch (this) {
//         _QualityMode.native => 1.0,
//         _QualityMode.adaptive => 0.5,
//         _QualityMode.aggressive => 0.25,
//       };
// }
//
// class _DragResult {
//   const _DragResult({
//     required this.seconds,
//     required this.callbackHz,
//     required this.p95GapMs,
//     required this.longGaps,
//     required this.maxGapMs,
//     required this.cameraChanges,
//     required this.renderRatio,
//     required this.pixelSize,
//   });
//
//   final double seconds;
//   final double callbackHz;
//   final double p95GapMs;
//   final int longGaps;
//   final double maxGapMs;
//   final int cameraChanges;
//   final double? renderRatio;
//   final String pixelSize;
//
//   factory _DragResult.fromJson(Map<String, dynamic> data) {
//     double number(String key) => (data[key] as num?)?.toDouble() ?? 0;
//     return _DragResult(
//       seconds: number('durationMs') / 1000,
//       callbackHz: number('callbackHz'),
//       p95GapMs: number('p95GapMs'),
//       longGaps: (data['longGaps'] as num?)?.toInt() ?? 0,
//       maxGapMs: number('maxGapMs'),
//       cameraChanges: (data['cameraChanges'] as num?)?.toInt() ?? 0,
//       renderRatio: (data['renderRatio'] as num?)?.toDouble(),
//       pixelSize: data['pixelSize']?.toString() ?? 'not reported',
//     );
//   }
// }
//
// /// Isolated A/B test of the SAME model-viewer engine used by Character Lab.
// /// The numbers are JavaScript requestAnimationFrame callback cadence, NOT
// /// exact GPU/composited WebGL FPS. No production model files are changed.
// class CharacterRenderBenchmarkScreen extends StatefulWidget {
//   const CharacterRenderBenchmarkScreen({super.key});
//
//   @override
//   State<CharacterRenderBenchmarkScreen> createState() =>
//       _CharacterRenderBenchmarkScreenState();
// }
//
// class _CharacterRenderBenchmarkScreenState
//     extends State<CharacterRenderBenchmarkScreen> {
//   static const _modelAsset = 'assets/models/navi_bust_uvsafe_52k.glb';
//   _QualityMode _mode = _QualityMode.native;
//   final Map<_QualityMode, List<_DragResult>> _results = {
//     for (final mode in _QualityMode.values) mode: <_DragResult>[],
//   };
//   final Map<_QualityMode, int> _loadMs = {};
//   final Stopwatch _loadTimer = Stopwatch()..start();
//   int _generation = 0;
//   bool _loaded = false;
//   String? _error;
//   String _engineStatus = 'Waiting for model-viewer…';
//   String _scaleStatus = 'Not reported yet';
//   bool? _scaleSupported;
//   dynamic _webController;
//
//   void _select(_QualityMode next) {
//     if (next == _mode) return;
//     setState(() {
//       _mode = next;
//       _generation++;
//       _loaded = false;
//       _error = null;
//       _engineStatus = 'Waiting for model-viewer…';
//       _scaleStatus = 'Not reported yet';
//       _scaleSupported = null;
//       _webController = null;
//       _loadTimer
//         ..reset()
//         ..start();
//     });
//   }
//
//   void _receive(dynamic payload, _QualityMode source, int generation) {
//     if (!mounted || source != _mode || generation != _generation) return;
//     try {
//       final dynamic decoded = payload is String ? jsonDecode(payload) : payload;
//       if (decoded is! Map) return;
//       final data = Map<String, dynamic>.from(decoded);
//       if (data['type'] == 'ready') {
//         setState(() {
//           _engineStatus = 'JavaScript measurement active';
//           _scaleSupported = data['scaleSupported'] == true;
//           _scaleStatus = _scaleSupported!
//               ? 'Minimum scale set to ${source.minimumScale.toStringAsFixed(2)}'
//               : 'Adaptive scale property unavailable in bundled viewer';
//         });
//       } else if (data['type'] == 'scale') {
//         final ratio = (data['ratio'] as num?)?.toDouble();
//         final size = data['pixelSize']?.toString() ?? 'unknown';
//         setState(() {
//           _scaleStatus = ratio == null
//               ? 'Render scale not reported'
//               : '${(ratio * 100).toStringAsFixed(0)}% rendered DPR · $size px';
//         });
//       } else if (data['type'] == 'drag') {
//         final result = _DragResult.fromJson(data);
//         if (result.seconds < 0.7) return;
//         setState(() => _results[source]!.add(result));
//       } else if (data['type'] == 'error') {
//         setState(() => _engineStatus = data['message']?.toString() ?? 'Probe failed');
//       }
//     } catch (_) {
//       // The benchmark must never interfere with the 3D viewer.
//     }
//   }
//
//   Future<void> _installProbe(_QualityMode mode, int generation) async {
//     final controller = _webController;
//     if (controller == null) return;
//     final script = _javascriptProbe.replaceAll(
//       '__MINIMUM_SCALE__',
//       mode.minimumScale.toString(),
//     );
//     try {
//       await controller.evaluateJavascript(source: script);
//     } catch (error) {
//       if (mounted && generation == _generation) {
//         setState(() => _engineStatus = 'Probe injection failed: $error');
//       }
//     }
//   }
//
//   String _report() {
//     final buffer = StringBuffer()
//       ..writeln('NAVI · Render resolution benchmark')
//       ..writeln('Model: UV-safe 52K')
//       ..writeln('Device: TECNO KI7 (confirm) / profile build recommended')
//       ..writeln('Gesture interception: OFF')
//       ..writeln('NOTE: rAF callback cadence is NOT guaranteed WebGL/GPU FPS.')
//       ..writeln('NOTE: minimumRenderScale is an adaptive FLOOR, not a fixed DPR.')
//       ..writeln('Last render-scale event: $_scaleStatus')
//       ..writeln('Adaptive scale supported: ${_scaleSupported ?? 'unknown'}')
//       ..writeln();
//     for (final mode in _QualityMode.values) {
//       final runs = _results[mode]!;
//       buffer.writeln('${mode.label} · minimum scale ${mode.minimumScale}: '
//           'load ${_loadMs[mode] ?? 'n/a'} ms, ${runs.length} drags');
//       for (var i = 0; i < runs.length; i++) {
//         final r = runs[i];
//         buffer.writeln('  Drag ${i + 1}: ${r.seconds.toStringAsFixed(1)}s; '
//             'rAF ${r.callbackHz.toStringAsFixed(1)} callbacks/s; '
//             'p95 gap ${r.p95GapMs.toStringAsFixed(1)}ms; '
//             'worst ${r.maxGapMs.toStringAsFixed(1)}ms; '
//             '>33ms ${r.longGaps}; camera-change ${r.cameraChanges}; '
//             'render DPR ${r.renderRatio == null ? 'unknown' : '${(r.renderRatio! * 100).toStringAsFixed(0)}%'}; '
//             'pixels ${r.pixelSize}');
//       }
//     }
//     return buffer.toString();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final scheme = Theme.of(context).colorScheme;
//     final runs = _results[_mode]!;
//     final average = runs.isEmpty
//         ? null
//         : runs.map((r) => r.callbackHz).reduce((a, b) => a + b) /
//             runs.length;
//     final currentMode = _mode;
//     final currentGeneration = _generation;
//
//     return Scaffold(
//       appBar: AppBar(title: const Text('NAVI · Render Benchmark')),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
//           child: Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 540),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.stretch,
//                 children: [
//                   Text('52K CHARACTER · CONTROLLED RENDER TEST',
//                       style: TextStyle(
//                           fontSize: 10,
//                           letterSpacing: 1.4,
//                           fontWeight: FontWeight.w700,
//                           color: scheme.primary)),
//                   const SizedBox(height: 9),
//                   Text('Find Navi’s smoothest setting',
//                       style: Theme.of(context).textTheme.titleLarge),
//                   const SizedBox(height: 9),
//                   const Text(
//                     'Compare full resolution with two adaptive quality floors. '
//                     'These are minimum scales: the viewer may stay at higher '
//                     'resolution if it does not need to scale down.',
//                     style: TextStyle(fontSize: 12, height: 1.5),
//                   ),
//                   const SizedBox(height: 12),
//                   Wrap(
//                     spacing: 7,
//                     runSpacing: 7,
//                     children: [
//                       for (final mode in _QualityMode.values)
//                         ChoiceChip(
//                           selected: mode == _mode,
//                           showCheckmark: false,
//                           label: Text('${mode.label} · ${mode.minimumScale}',
//                               style: const TextStyle(fontSize: 11)),
//                           onSelected: (_) => _select(mode),
//                         ),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   Container(
//                     height: 365,
//                     clipBehavior: Clip.antiAlias,
//                     decoration: BoxDecoration(
//                       border: Border.all(color: scheme.outlineVariant),
//                       color: const Color(0xFF0A152A),
//                       borderRadius: BorderRadius.circular(24),
//                     ),
//                     child: Stack(
//                       children: [
//                         Positioned.fill(
//                           child: ModelViewer(
//                             key: ValueKey('bench-${currentMode.name}-$currentGeneration'),
//                             id: 'navi-perf-model',
//                             src: _modelAsset,
//                             cameraControls: true,
//                             autoRotate: false,
//                             autoPlay: false,
//                             ar: false,
//                             disableTap: true,
//                             interactionPrompt: InteractionPrompt.none,
//                             activeGestureInterceptor: false,
//                             debugLogging: false,
//                             progressBarColor: const Color(0xFF4D8BFF),
//                             onWebViewCreated: (controller) {
//                               _webController = controller;
//                               controller.addJavaScriptHandler(
//                                 handlerName: 'naviPerfProbe',
//                                 callback: (args) {
//                                   if (args.isNotEmpty) {
//                                     _receive(args.first, currentMode, currentGeneration);
//                                   }
//                                   return null;
//                                 },
//                               );
//                             },
//                             onLoad: (_) {
//                               if (!mounted || currentGeneration != _generation) return;
//                               _loadTimer.stop();
//                               setState(() {
//                                 _loaded = true;
//                                 _loadMs[currentMode] = _loadTimer.elapsedMilliseconds;
//                               });
//                               _installProbe(currentMode, currentGeneration);
//                             },
//                             onError: (error) {
//                               if (!mounted || currentGeneration != _generation) return;
//                               setState(() => _error = error);
//                             },
//                           ),
//                         ),
//                         if (!_loaded)
//                           Positioned(
//                             top: 14,
//                             left: 14,
//                             right: 14,
//                             child: Text(
//                               _error ?? 'Loading the model…',
//                               style: const TextStyle(
//                                   color: Color(0xFFEAF1FF), fontSize: 12),
//                             ),
//                           ),
//                         const Positioned(
//                           bottom: 12,
//                           left: 16,
//                           right: 16,
//                           child: IgnorePointer(
//                             child: Text(
//                               'DRAG SLOWLY AND CONTINUOUSLY FOR 8–10 SECONDS',
//                               textAlign: TextAlign.center,
//                               style: TextStyle(
//                                 color: Color(0xFF85B5FF),
//                                 fontSize: 10,
//                                 letterSpacing: .4,
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 14),
//                   Container(
//                     padding: const EdgeInsets.all(14),
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(16),
//                       color: scheme.surfaceContainerHighest.withValues(alpha: .45),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text('BENCHMARK STATUS',
//                             style: TextStyle(
//                               fontSize: 10,
//                               letterSpacing: 1,
//                               color: scheme.primary,
//                               fontWeight: FontWeight.w700,
//                             )),
//                         const SizedBox(height: 8),
//                         Text('Probe: $_engineStatus',
//                             style: const TextStyle(fontSize: 12)),
//                         const SizedBox(height: 4),
//                         Text('Render scale: $_scaleStatus',
//                             style: const TextStyle(fontSize: 12)),
//                         const SizedBox(height: 4),
//                         Text('Load: ${_loadMs[_mode] ?? '…'} ms · Drags: ${runs.length}',
//                             style: const TextStyle(fontSize: 12)),
//                         if (average != null) ...[
//                           const SizedBox(height: 8),
//                           Text(
//                             'Mean rAF callback cadence: ${average.toStringAsFixed(1)} / sec',
//                             style: const TextStyle(fontWeight: FontWeight.w700),
//                           ),
//                         ],
//                         const SizedBox(height: 6),
//                         const Text(
//                           'This is JavaScript callback timing during a drag. '
//                           'It is NOT GPU frame time or confirmed rendered FPS.',
//                           style: TextStyle(fontSize: 11, height: 1.4),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 14),
//                   FilledButton.icon(
//                     onPressed: () async {
//                       await Clipboard.setData(ClipboardData(text: _report()));
//                       if (!context.mounted) return;
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(content: Text('Benchmark report copied')),
//                       );
//                     },
//                     icon: const Icon(Icons.copy),
//                     label: const Text('Copy all three test results'),
//                   ),
//                   const SizedBox(height: 8),
//                   const Text(
//                     'Test Full → Adaptive → Adaptive low. Rotate 3 times per '
//                     'setting, 8–10 seconds each. Allow the phone to cool between '
//                     'tests and note if the image looks blurrier. This test leaves '
//                     'the regular Character Lab unchanged.',
//                     style: TextStyle(fontSize: 11.5, height: 1.5),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// const String _javascriptProbe = r'''
// (() => {
//   // Diagnostic script; runs only inside the dedicated benchmark viewer.
//   if (window.__naviProbe?.dispose) window.__naviProbe.dispose();
//   const mv = document.querySelector('model-viewer');
//   if (!mv) return;
//   const minScale = __MINIMUM_SCALE__;
//   const ctor = customElements.get('model-viewer');
//   const scaleSupported = !!ctor && ('minimumRenderScale' in ctor);
//   if (scaleSupported) ctor.minimumRenderScale = minScale;
//
//   let renderRatio = null;
//   let pixelSize = 'not reported';
//   let active = false;
//   let begun = 0;
//   let last = null;
//   let intervals = [];
//   let changes = 0;
//   let frameId = 0;
//   let pointerId = null;
//   const send = (obj) => {
//     try {
//       window.flutter_inappwebview?.callHandler('naviPerfProbe', JSON.stringify(obj));
//     } catch (_) {}
//   };
//   const scaleChanged = (ev) => {
//     const d = ev.detail || {};
//     const reported = Number(d.reportedDpr);
//     const rendered = Number(d.renderedDpr);
//     renderRatio = Number.isFinite(reported) && reported > 0 &&
//         Number.isFinite(rendered) ? rendered / reported : null;
//     pixelSize = d.pixelWidth && d.pixelHeight
//       ? `${d.pixelWidth} x ${d.pixelHeight}` : 'not reported';
//     send({ type: 'scale', ratio: renderRatio, pixelSize });
//   };
//   const changed = () => { if (active) changes++; };
//   const tick = (t) => {
//     if (!active) return;
//     if (last !== null) intervals.push(t - last);
//     last = t;
//     frameId = requestAnimationFrame(tick);
//   };
//   const start = (e) => {
//     if (active || (e.pointerType === 'mouse' && e.button !== 0)) return;
//     pointerId = e.pointerId;
//     active = true;
//     begun = performance.now();
//     last = null;
//     intervals = [];
//     changes = 0;
//     frameId = requestAnimationFrame(tick);
//   };
//   const finish = (e) => {
//     if (!active || (e && pointerId != null && e.pointerId !== pointerId)) return;
//     active = false;
//     cancelAnimationFrame(frameId);
//     const durationMs = performance.now() - begun;
//     pointerId = null;
//     if (durationMs < 700 || intervals.length < 10) return;
//     const arr = intervals.filter(x => x > 0 && Number.isFinite(x));
//     if (arr.length < 10) return;
//     const sorted = arr.slice().sort((a, b) => a - b);
//     const sum = arr.reduce((a, b) => a + b, 0);
//     send({
//       type: 'drag',
//       durationMs,
//       callbackHz: arr.length * 1000 / sum,
//       p95GapMs: sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1)],
//       maxGapMs: sorted[sorted.length - 1],
//       longGaps: arr.filter(x => x > 33.3).length,
//       cameraChanges: changes,
//       renderRatio,
//       pixelSize
//     });
//   };
//   mv.addEventListener('render-scale', scaleChanged);
//   mv.addEventListener('camera-change', changed);
//   mv.addEventListener('pointerdown', start, true);
//   window.addEventListener('pointerup', finish, true);
//   window.addEventListener('pointercancel', finish, true);
//   window.__naviProbe = {
//     dispose: () => {
//       active = false;
//       cancelAnimationFrame(frameId);
//       mv.removeEventListener('render-scale', scaleChanged);
//       mv.removeEventListener('camera-change', changed);
//       mv.removeEventListener('pointerdown', start, true);
//       window.removeEventListener('pointerup', finish, true);
//       window.removeEventListener('pointercancel', finish, true);
//     }
//   };
//   send({type: 'ready', scaleSupported, minScale});
// })();
// ''';
