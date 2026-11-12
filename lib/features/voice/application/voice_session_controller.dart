import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/android_voice_output.dart';
import '../data/groq_speech_engine.dart';
import '../data/pcm_audio_levels.dart';
import '../domain/local_command_router.dart';
import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'voice_dependencies.dart';

final voiceSessionProvider =
    NotifierProvider<VoiceSessionController, VoiceSessionState>(
      VoiceSessionController.new,
    );

/// Exposes live microphone energy [0.0..1.0] as a [ValueListenable] so the
/// companion cloud can repaint at audio rate without rebuilding widget trees.
final voiceAudioLevelProvider = Provider<ValueListenable<double>>(
  (ref) => ref.watch(voiceSessionProvider.notifier).audioLevel,
);

/// Owns the foreground voice session. Widgets send intent and visibility only.
/// Session and utterance IDs guard every asynchronous result and native event.
class VoiceSessionController extends Notifier<VoiceSessionState> {
  static const commandTimeout = Duration(seconds: 14);
  static const followUpTimeout = Duration(seconds: 8);
  static const audioMeterWindowSamples = 800; // 50 ms at 16 kHz mono PCM16.
  final _commands = const LocalCommandRouter();
  final _audioMeter = PcmAudioMeter(windowSamples: audioMeterWindowSamples);
  final _audioLevel = ValueNotifier<double>(0.0);
  late VoiceServices _services;
  _VoiceRun? _run;
  Future<void> _operations = Future.value();
  Future<void> _preferenceWrites = Future.value();
  Timer? _deadline;
  Timer? _startupDeadline;
  int _generation = 0;
  int _runGeneration = -1;
  int _settingsRevision = 0;
  int _utteranceId = 0;
  int _destinationRevision = 0;
  int _checklistRevision = 0;
  bool _enabled = false;
  final _visibleSurfaces = <String>{};
  bool _foreground = true;
  bool _disposed = false;
  bool _wakeTurn = false;
  bool _isCasual = false;
  String _rawTranscript = '';
  String _reply = '';
  String? _destination;
  String? _purposeSummary;
  Stopwatch? _responseClock;
  List<String> _checklist = const <String>[];

  ValueListenable<double> get audioLevel => _audioLevel;

  bool get _homeVisible => _visibleSurfaces.isNotEmpty;
  bool get _shouldRun => _enabled && _homeVisible && _foreground && !_disposed;

  @override
  VoiceSessionState build() {
    _services = ref.read(voiceServicesProvider);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _deadline?.cancel();
      _startupDeadline?.cancel();
      _audioMeter.reset();
      _audioLevel.dispose();
      final run = _run;
      _run = null;
      if (run != null) unawaited(run.dispose());
    });
    Future.microtask(_restore);
    return const VoiceSessionState();
  }

  Future<void> _restore() async {
    if (!_services.wakeRequired) return;
    final revision = _settingsRevision;
    try {
      final enabled = await _services.preferences.readEnabled();
      if (_disposed || revision != _settingsRevision) return;
      _enabled = enabled;
      if (enabled) await _reconcile(requestPermission: false);
    } catch (_) {
      // Native preferences may be unavailable in tests or unsupported hosts.
      // A failed read always defaults to no microphone access.
    }
  }

  Future<void> setEnabled(
    bool enabled, {
    bool requestPermission = false,
  }) async {
    if (_disposed) return;
    _settingsRevision++;
    _enabled = enabled;
    _invalidate();
    _publish(
      enabled
          ? (_shouldRun ? VoicePhase.preparing : VoicePhase.suspended)
          : VoicePhase.off,
    );
    final revision = _settingsRevision;
    // Disk/plugin latency must not delay microphone startup. Writes remain
    // ordered so a rapid on/off sequence persists the latest user choice.
    _preferenceWrites = _preferenceWrites
        .then((_) => _services.preferences.writeEnabled(enabled))
        .catchError((Object _) {});
    if (_disposed || revision != _settingsRevision) return;
    await _reconcile(requestPermission: requestPermission);
  }

  Future<void> retry() => setEnabled(true, requestPermission: true);

  /// Handles a Push-to-Talk microphone button press across all phases:
  /// - If off/error: starts a new listening turn.
  /// - If listening and speech was already captured: flushes the utterance immediately.
  /// - If speaking: interrupts TTS playback and starts a fresh listening turn.
  /// - Otherwise: stops the active session.
  Future<void> togglePushToTalk() async {
    if (_disposed) return;
    if (state.phase == VoicePhase.error || !_enabled) {
      await setEnabled(true, requestPermission: true);
      return;
    }
    if (state.phase == VoicePhase.listening) {
      final speech = _run?.speech;
      if (speech is GroqSpeechEngine && speech.flushUtterance()) {
        return;
      }
      await setEnabled(false);
      return;
    }
    if (state.phase == VoicePhase.speaking) {
      await setEnabled(false);
      await setEnabled(true, requestPermission: true);
      return;
    }
    await setEnabled(false);
  }

  /// Scheduled outside widget build/disposal so providers are never mutated
  /// synchronously while the widget tree is being assembled.
  void setHomeVisible(bool visible) => setSurfaceVisible('home', visible);

  void setSurfaceVisible(String owner, bool visible) {
    if (_disposed) return;
    final wasVisible = _homeVisible;
    if (visible) {
      _visibleSurfaces.add(owner);
    } else {
      _visibleSurfaces.remove(owner);
    }
    if (wasVisible == _homeVisible) return;
    _prepareVisibleSpeech();
    _invalidate();
    Future.microtask(() {
      if (!_disposed) unawaited(_reconcile(requestPermission: false));
    });
  }

  void setForeground(bool foreground, {bool releaseModels = true}) {
    if (_disposed) return;
    if (foreground == _foreground) {
      if (!foreground && releaseModels) _services.coolSpeech?.call();
      return;
    }
    _foreground = foreground;
    if (foreground || releaseModels) _prepareVisibleSpeech();
    _invalidate();
    unawaited(_reconcile(requestPermission: false));
  }

  void suspendForNavigation() => setHomeVisible(false);

  void _prepareVisibleSpeech() {
    if (_homeVisible && _foreground) {
      final warm = _services.warmSpeech;
      if (warm != null) unawaited(warm().catchError((Object _) {}));
    } else {
      _services.coolSpeech?.call();
    }
  }

  void _resetAudioLevel() {
    _audioMeter.reset();
    if (!_disposed && _audioLevel.value != 0.0) {
      _audioLevel.value = 0.0;
    }
  }

  void _onAudioChunk(_VoiceRun run, int generation, Uint8List bytes) {
    if (!_current(run, generation)) return;
    run.speech.addAudio(bytes);
    final readings = _audioMeter.add(bytes);
    if (readings.isNotEmpty) {
      final target = readings.last.normalizedLevel;
      final current = _audioLevel.value;
      // Asymmetric envelope follower: fast attack (0.65) for speech onset,
      // smooth release (0.35) for organic cloud decay.
      final factor = target >= current ? 0.65 : 0.35;
      final smoothed = current + (target - current) * factor;
      _audioLevel.value = smoothed < 0.005 ? 0.0 : smoothed;
    }
  }

  void _invalidate() {
    _generation++;
    _deadline?.cancel();
    _startupDeadline?.cancel();
    _resetAudioLevel();
    final run = _run;
    if (run != null) {
      run.cancelled = true;
      run.speech.setMode(SpeechMode.muted);
      unawaited(run.microphone.stop().catchError((Object _) {}));
      unawaited(run.output.stopSpeaking().catchError((Object _) {}));
      unawaited(run.dispose());
    }
  }

  Future<void> _reconcile({required bool requestPermission}) {
    final generation = _generation;
    _operations = _operations
        .then((_) async {
          if (_disposed || generation != _generation) return;
          // Visibility and preference restoration can enqueue the same start.
          // A failed run waits for an explicit retry rather than starting twice.
          if (_run != null && _runGeneration == generation) return;
          final previous = _run;
          _run = null;
          await previous?.dispose();
          if (_disposed || generation != _generation) return;
          if (!_shouldRun) {
            _publish(_enabled ? VoicePhase.suspended : VoicePhase.off);
            return;
          }
          final run = _VoiceRun(
            _services.microphone(),
            _services.speech(),
            _services.output(),
          );
          _run = run;
          _runGeneration = generation;
          _publish(VoicePhase.preparing);
          try {
            if (!await run.microphone
                .hasPermission(request: requestPermission)
                .timeout(
                  requestPermission
                      ? const Duration(minutes: 2)
                      : const Duration(seconds: 3),
                  onTimeout: () =>
                      throw const VoiceException(VoiceFailure.startupTimeout),
                )) {
              throw const VoiceException(VoiceFailure.permissionDenied);
            }
            if (!_current(run, generation)) return;
            final startup = Stopwatch()..start();
            _startupDeadline = Timer(_services.startupTimeout, () {
              unawaited(_fail(run, generation, VoiceFailure.startupTimeout));
            });
            run.speechEvents = run.speech.events.listen(
              (event) => _speechEvent(run, generation, event),
            );
            run.outputEvents = run.output.events.listen(
              (event) => _outputEvent(run, generation, event),
            );
            // Output preparation has its own result and deadline. It must not
            // prevent a ready wake detector from opening capture.
            run.prepareOutput();
            await run.whileActive(run.speech.initialize());
            if (!_current(run, generation)) return;
            await _listen(run, generation, wakeOnly: _services.wakeRequired);
            if (_current(run, generation)) {
              _startupDeadline?.cancel();
              developer.log(
                'Hands-free ready in ${startup.elapsedMilliseconds}ms',
                name: 'NAVI.voice',
              );
            }
          } catch (error) {
            await _fail(run, generation, _failure(error));
          } finally {
            if (!_current(run, generation)) await run.dispose();
          }
        })
        .catchError((Object _) {
          if (!_disposed && generation == _generation) {
            _publish(VoicePhase.error, failure: VoiceFailure.microphone);
          }
        });
    return _operations;
  }

  bool _current(_VoiceRun run, int generation) =>
      !_disposed &&
      _shouldRun &&
      !run.cancelled &&
      identical(run, _run) &&
      generation == _generation;

  void _publish(VoicePhase phase, {VoiceFailure? failure}) {
    if (_disposed) return;
    final cleanedTranscript = _commands.removeWakePhrase(
      _rawTranscript,
      wakeDetected: _wakeTurn,
    );
    final effectiveTranscript =
        cleanedTranscript.isEmpty && !_services.wakeRequired
        ? _rawTranscript.trim()
        : cleanedTranscript;
    state = VoiceSessionState(
      enabled: _enabled,
      phase: phase,
      transcript: effectiveTranscript,
      reply: _reply,
      failure: failure,
      destination: _destination,
      destinationRevision: _destinationRevision,
      purposeSummary: _purposeSummary,
      isCasual: _isCasual,
      checklist: _checklist,
      checklistRevision: _checklistRevision,
    );
  }

  Future<void> _listen(
    _VoiceRun run,
    int generation, {
    required bool wakeOnly,
  }) async {
    if (!_current(run, generation)) return;
    _resetAudioLevel();
    await run.stopMicrophone();
    if (!_current(run, generation)) return;
    run.speech.setMode(wakeOnly ? SpeechMode.wake : SpeechMode.listening);
    final audio = await run.microphone.start();
    if (!_current(run, generation)) {
      await run.microphone.stop();
      return;
    }
    run.audio = audio.listen(
      (bytes) => _onAudioChunk(run, generation, bytes),
      onError: (Object error) =>
          unawaited(_fail(run, generation, _failure(error))),
      onDone: () {
        if (_current(run, generation) && run.audio != null) {
          unawaited(_fail(run, generation, VoiceFailure.interrupted));
        }
      },
    );
    _rawTranscript = '';
    _responseClock = null;
    _wakeTurn = !wakeOnly && !_services.wakeRequired;
    _publish(wakeOnly ? VoicePhase.armed : VoicePhase.listening);
    _deadline?.cancel();
    if (!wakeOnly) {
      final timeout = _services.wakeRequired ? followUpTimeout : commandTimeout;
      _deadline = Timer(timeout, () {
        if (!_current(run, generation) || state.phase != VoicePhase.listening) {
          return;
        }
        if (_rawTranscript.trim().isNotEmpty) {
          unawaited(_answer(run, generation, _rawTranscript));
        } else if (!_services.wakeRequired) {
          unawaited(setEnabled(false));
        } else {
          unawaited(
            _listen(run, generation, wakeOnly: true).catchError(
              (Object error) => _fail(run, generation, _failure(error)),
            ),
          );
        }
      });
    }
  }

  void _speechEvent(_VoiceRun run, int generation, SpeechEvent event) {
    if (!_current(run, generation)) return;
    switch (event) {
      case SpeechStarted():
        if (state.phase != VoicePhase.listening) return;
        _deadline?.cancel();
        _deadline = Timer(const Duration(seconds: 35), () {
          unawaited(_fail(run, generation, VoiceFailure.utteranceTooLong));
        });
      case TranscriptionStarted():
        if (state.phase != VoicePhase.listening) return;
        _deadline?.cancel();
        _reply = '';
        _responseClock = Stopwatch()..start();
        _publish(VoicePhase.transcribing);
        _deadline = Timer(const Duration(seconds: 12), () {
          unawaited(_fail(run, generation, VoiceFailure.unavailable));
        });
      case ListeningResumed():
        if (state.phase != VoicePhase.transcribing) return;
        _deadline?.cancel();
        _publish(VoicePhase.listening);
        _deadline = Timer(commandTimeout, () {
          if (_current(run, generation)) unawaited(setEnabled(false));
        });
      case WakeDetected():
        if (state.phase != VoicePhase.armed) return;
        _wakeTurn = true;
        _rawTranscript = '';
        _publish(VoicePhase.listening);
        _deadline?.cancel();
        _deadline = Timer(commandTimeout, () {
          if (_current(run, generation) &&
              state.phase == VoicePhase.listening) {
            unawaited(_answer(run, generation, _rawTranscript));
          }
        });
      case TranscriptChanged(:final text):
        if (state.phase != VoicePhase.listening &&
            state.phase != VoicePhase.transcribing) {
          return;
        }
        _rawTranscript = text;
        _publish(state.phase);
      case UtteranceEnded(:final text):
        if (state.phase != VoicePhase.listening &&
            state.phase != VoicePhase.transcribing) {
          return;
        }
        if (!_wakeTurn && text.trim().isEmpty) {
          if (!_services.wakeRequired) {
            unawaited(setEnabled(false));
          } else {
            unawaited(
              _listen(run, generation, wakeOnly: true).catchError(
                (Object error) => _fail(run, generation, _failure(error)),
              ),
            );
          }
        } else {
          unawaited(_answer(run, generation, text));
        }
      case SpeechFailed(:final failure):
        unawaited(_fail(run, generation, failure));
    }
  }

  void _outputEvent(_VoiceRun run, int generation, OutputEvent event) {
    if (!_current(run, generation) || event.id != _utteranceId) return;
    if (event.type == OutputEventType.started &&
        state.phase == VoicePhase.preparingReply) {
      _publish(VoicePhase.speaking);
      if (const bool.fromEnvironment('NAVI_VOICE_DIAGNOSTICS') &&
          _responseClock != null) {
        developer.log(
          'stage=first_audio responseMs=${_responseClock!.elapsedMilliseconds}',
          name: 'NAVI.voice',
        );
      }
    } else if (event.type == OutputEventType.failed ||
        event.type == OutputEventType.cancelled) {
      unawaited(_fail(run, generation, VoiceFailure.output));
    }
  }

  Future<void> _answer(_VoiceRun run, int generation, String text) async {
    if (!_current(run, generation) ||
        (state.phase != VoicePhase.listening &&
            state.phase != VoicePhase.transcribing)) {
      return;
    }
    _deadline?.cancel();
    run.speech.setMode(SpeechMode.muted);
    _rawTranscript = text;
    final wakeTurn = _wakeTurn;
    final reasoner = _services.reasoner;
    LocalReply? response;
    if (reasoner is LocalCommandRouter) {
      response = reasoner.route(text, wakeDetected: wakeTurn);
      _applyReply(response);
    }
    _publish(VoicePhase.preparingReply);
    try {
      // Releasing the mic prevents Navi from recognizing its own voice.
      _resetAudioLevel();
      final LocalReply resolved;
      if (response != null) {
        resolved = response;
        await run.stopMicrophone();
      } else {
        // Play a natural 0.4s backchannel ("Mm-hmm.", "Yeah...", "True...")
        // immediately from RAM while the LLM and TTS prepare the full reply.
        if (run.output is AndroidVoiceOutput &&
            text.trim().split(RegExp(r'\s+')).length >= 3) {
          (run.output as AndroidVoiceOutput).playBackchannelFiller();
        }
        // Start reasoning while native microphone shutdown completes. Recognition
        // is already muted, and output still waits until microphone release.
        final results = await run.whileActive(
          Future.wait<Object?>([
            reasoner.resolve(text, wakeDetected: wakeTurn),
            run.stopMicrophone(),
          ]),
        );
        resolved = results.first as LocalReply;
        if (!_current(run, generation)) return;
        _applyReply(resolved);
        _publish(VoicePhase.preparingReply);
      }
      await run.whileActive(run.outputReady);
      if (!_current(run, generation)) return;
      final id = ++_utteranceId;
      await run.output.speak(resolved.text, id: id);
      if (!_current(run, generation)) return;
      if (resolved.intent == LocalIntent.sleep ||
          (!resolved.followUp && !_services.wakeRequired)) {
        await setEnabled(false);
      } else {
        await _listen(
          run,
          generation,
          wakeOnly: !resolved.followUp && _services.wakeRequired,
        );
      }
    } catch (error) {
      await _fail(run, generation, _failure(error));
    }
  }

  void _applyReply(LocalReply response) {
    _reply = response.text;
    if (response.destination != null) {
      final isDifferentDestination =
          _destination?.toLowerCase() != response.destination!.toLowerCase();
      _destination = response.destination;
      _destinationRevision++;
      if (isDifferentDestination) {
        _purposeSummary = null;
        _isCasual = false;
        _checklist = const <String>[];
        _checklistRevision++;
      }
    }
    if (response.purposeSummary != null ||
        response.checklist.isNotEmpty ||
        response.isCasual) {
      _purposeSummary = response.purposeSummary ?? _purposeSummary;
      _isCasual = response.isCasual;
      if (response.isCasual) {
        _checklist = const <String>[];
      } else if (response.checklist.isNotEmpty) {
        _checklist = List<String>.unmodifiable(response.checklist);
      }
      _checklistRevision++;
    }
  }

  Future<void> _fail(
    _VoiceRun run,
    int generation,
    VoiceFailure failure,
  ) async {
    if (!_current(run, generation)) return;
    run.cancelled = true;
    _deadline?.cancel();
    _startupDeadline?.cancel();
    _resetAudioLevel();
    _publish(VoicePhase.error, failure: failure);
    await run.dispose();
  }

  VoiceFailure _failure(Object error) =>
      error is VoiceException ? error.failure : VoiceFailure.microphone;
}

class _VoiceRun {
  _VoiceRun(this.microphone, this.speech, this.output);
  final MicrophoneInput microphone;
  final SpeechEngine speech;
  final VoiceGateway output;
  StreamSubscription<Uint8List>? audio;
  StreamSubscription<SpeechEvent>? speechEvents;
  StreamSubscription<OutputEvent>? outputEvents;
  bool cancelled = false;
  Future<void>? _disposing;
  final _cancelled = Completer<void>();
  Future<void>? _preparingOutput;
  Object? _outputFailure;

  Future<T> whileActive<T>(Future<T> operation) => Future.any<T>([
    operation,
    _cancelled.future.then<T>(
      (_) => throw const VoiceException(VoiceFailure.interrupted),
    ),
  ]);

  void prepareOutput() {
    _preparingOutput ??= () async {
      try {
        await output.initialize().timeout(const Duration(seconds: 10));
      } catch (error) {
        _outputFailure = error is VoiceException
            ? error
            : const VoiceException(VoiceFailure.output);
      }
    }();
  }

  Future<void> get outputReady async {
    prepareOutput();
    await _preparingOutput;
    if (_outputFailure != null) throw _outputFailure!;
  }

  Future<void> stopMicrophone() async {
    final subscription = audio;
    audio = null;
    await subscription?.cancel();
    await microphone.stop();
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    cancelled = true;
    if (!_cancelled.isCompleted) _cancelled.complete();
    await speechEvents?.cancel();
    await outputEvents?.cancel();
    for (final cleanup in <Future<void> Function()>[
      stopMicrophone,
      output.stopSpeaking,
      speech.dispose,
      microphone.dispose,
      output.dispose,
    ]) {
      try {
        await cleanup();
      } catch (_) {
        /* Continue releasing other resources. */
      }
    }
  }
}
