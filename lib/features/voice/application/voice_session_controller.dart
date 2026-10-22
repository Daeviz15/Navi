import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/local_command_router.dart';
import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'voice_dependencies.dart';

final voiceSessionProvider = NotifierProvider<VoiceSessionController, VoiceSessionState>(VoiceSessionController.new);

/// Owns the foreground voice session. Widgets send intent and visibility only.
/// Session and utterance IDs guard every asynchronous result and native event.
class VoiceSessionController extends Notifier<VoiceSessionState> {
  static const commandTimeout = Duration(seconds: 14);
  static const followUpTimeout = Duration(seconds: 8);
  final _commands = const LocalCommandRouter();
  late VoiceServices _services;
  _VoiceRun? _run;
  Future<void> _operations = Future.value();
  Timer? _deadline;
  int _generation = 0;
  int _settingsRevision = 0;
  int _utteranceId = 0;
  int _destinationRevision = 0;
  bool _enabled = false;
  bool _homeVisible = false;
  bool _foreground = true;
  bool _disposed = false;
  bool _wakeTurn = false;
  String _rawTranscript = '';
  String _reply = '';
  String? _destination;

  bool get _shouldRun => _enabled && _homeVisible && _foreground && !_disposed;

  @override
  VoiceSessionState build() {
    _services = ref.watch(voiceServicesProvider);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _deadline?.cancel();
      final run = _run;
      _run = null;
      if (run != null) unawaited(run.dispose());
    });
    Future.microtask(_restore);
    return const VoiceSessionState();
  }

  Future<void> _restore() async {
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

  Future<void> setEnabled(bool enabled, {bool requestPermission = false}) async {
    if (_disposed) return;
    _settingsRevision++;
    _enabled = enabled;
    _invalidate();
    _publish(enabled ? (_shouldRun ? VoicePhase.preparing : VoicePhase.suspended) : VoicePhase.off);
    final revision = _settingsRevision;
    try {
      await _services.preferences.writeEnabled(enabled);
    } catch (_) {
      // The current session still works; no audio or transcript is persisted.
    }
    if (_disposed || revision != _settingsRevision) return;
    await _reconcile(requestPermission: requestPermission);
  }

  Future<void> retry() => setEnabled(true, requestPermission: true);

  /// Scheduled outside widget build/disposal so providers are never mutated
  /// synchronously while the widget tree is being assembled.
  void setHomeVisible(bool visible) {
    if (_disposed || visible == _homeVisible) return;
    _homeVisible = visible;
    _invalidate();
    Future.microtask(() {
      if (!_disposed) unawaited(_reconcile(requestPermission: false));
    });
  }

  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    _invalidate();
    unawaited(_reconcile(requestPermission: false));
  }

  void _invalidate() {
    _generation++;
    _deadline?.cancel();
    final run = _run;
    if (run != null) {
      run.cancelled = true;
      run.speech.setMode(SpeechMode.muted);
      unawaited(run.microphone.stop().catchError((Object _) {}));
      unawaited(run.output.stopSpeaking().catchError((Object _) {}));
    }
  }

  Future<void> _reconcile({required bool requestPermission}) {
    final generation = _generation;
    _operations = _operations.then((_) async {
      if (_disposed || generation != _generation) return;
      final previous = _run;
      _run = null;
      await previous?.dispose();
      if (_disposed || generation != _generation) return;
      if (!_shouldRun) {
        _publish(_enabled ? VoicePhase.suspended : VoicePhase.off);
        return;
      }
      final run = _VoiceRun(_services.microphone(), _services.speech(), _services.output());
      _run = run;
      _publish(VoicePhase.preparing);
      try {
        if (!await run.microphone.hasPermission(request: requestPermission)) {
          throw const VoiceException(VoiceFailure.permissionDenied);
        }
        if (!_current(run, generation)) return;
        run.speechEvents = run.speech.events.listen((event) => _speechEvent(run, generation, event));
        run.outputEvents = run.output.events.listen((event) => _outputEvent(run, generation, event));
        await run.output.initialize();
        if (!_current(run, generation)) return;
        await run.speech.initialize();
        if (!_current(run, generation)) return;
        await _listen(run, generation, wakeOnly: true);
      } catch (error) {
        await _fail(run, generation, _failure(error));
      } finally {
        if (!_current(run, generation)) await run.dispose();
      }
    }).catchError((Object _) {
      if (!_disposed && generation == _generation) _publish(VoicePhase.error, failure: VoiceFailure.microphone);
    });
    return _operations;
  }

  bool _current(_VoiceRun run, int generation) =>
      !_disposed && _shouldRun && !run.cancelled && identical(run, _run) && generation == _generation;

  void _publish(VoicePhase phase, {VoiceFailure? failure}) {
    if (_disposed) return;
    state = VoiceSessionState(enabled: _enabled, phase: phase,
      transcript: _commands.removeWakePhrase(_rawTranscript), reply: _reply,
      failure: failure, destination: _destination, destinationRevision: _destinationRevision);
  }

  Future<void> _listen(_VoiceRun run, int generation, {required bool wakeOnly}) async {
    if (!_current(run, generation)) return;
    await run.stopMicrophone();
    if (!_current(run, generation)) return;
    run.speech.setMode(wakeOnly ? SpeechMode.wake : SpeechMode.listening);
    final audio = await run.microphone.start();
    if (!_current(run, generation)) { await run.microphone.stop(); return; }
    run.audio = audio.listen(run.speech.addAudio,
      onError: (Object error) => unawaited(_fail(run, generation, _failure(error))),
      onDone: () {
        if (_current(run, generation) && run.audio != null) {
          unawaited(_fail(run, generation, VoiceFailure.interrupted));
        }
      });
    _rawTranscript = '';
    _wakeTurn = false;
    _publish(wakeOnly ? VoicePhase.armed : VoicePhase.listening);
    _deadline?.cancel();
    if (!wakeOnly) {
      _deadline = Timer(followUpTimeout, () {
        if (!_current(run, generation) || state.phase != VoicePhase.listening) return;
        if (_rawTranscript.trim().isNotEmpty) {
          unawaited(_answer(run, generation, _rawTranscript));
        } else {
          unawaited(_listen(run, generation, wakeOnly: true).catchError(
            (Object error) => _fail(run, generation, _failure(error))));
        }
      });
    }
  }

  void _speechEvent(_VoiceRun run, int generation, SpeechEvent event) {
    if (!_current(run, generation)) return;
    switch (event) {
      case WakeDetected():
        if (state.phase != VoicePhase.armed) return;
        _wakeTurn = true;
        _rawTranscript = '';
        _publish(VoicePhase.listening);
        _deadline?.cancel();
        _deadline = Timer(commandTimeout, () {
          if (_current(run, generation) && state.phase == VoicePhase.listening) {
            unawaited(_answer(run, generation, _rawTranscript));
          }
        });
      case TranscriptChanged(:final text):
        if (state.phase != VoicePhase.listening) return;
        _rawTranscript = text;
        _publish(VoicePhase.listening);
      case UtteranceEnded(:final text):
        if (state.phase != VoicePhase.listening) return;
        if (!_wakeTurn && text.trim().isEmpty) {
          unawaited(_listen(run, generation, wakeOnly: true).catchError(
            (Object error) => _fail(run, generation, _failure(error))));
        } else {
          unawaited(_answer(run, generation, text));
        }
      case SpeechFailed(:final failure):
        unawaited(_fail(run, generation, failure));
    }
  }

  void _outputEvent(_VoiceRun run, int generation, OutputEvent event) {
    if (!_current(run, generation) || event.id != _utteranceId) return;
    if (event.type == OutputEventType.started && state.phase == VoicePhase.preparingReply) {
      _publish(VoicePhase.speaking);
    } else if (event.type == OutputEventType.failed || event.type == OutputEventType.cancelled) {
      unawaited(_fail(run, generation, VoiceFailure.output));
    }
  }

  Future<void> _answer(_VoiceRun run, int generation, String text) async {
    if (!_current(run, generation) || state.phase != VoicePhase.listening) return;
    _deadline?.cancel();
    run.speech.setMode(SpeechMode.muted);
    _rawTranscript = text;
    final response = _commands.route(text);
    _reply = response.text;
    if (response.destination != null) {
      _destination = response.destination;
      _destinationRevision++;
    }
    _publish(VoicePhase.preparingReply);
    try {
      // Releasing the mic prevents Navi from recognizing its own voice.
      await run.stopMicrophone();
      if (!_current(run, generation)) return;
      final id = ++_utteranceId;
      await run.output.speak(response.text, id: id);
      if (!_current(run, generation)) return;
      if (response.intent == LocalIntent.sleep) {
        await setEnabled(false);
      } else {
        await _listen(run, generation, wakeOnly: !response.followUp);
      }
    } catch (error) {
      await _fail(run, generation, _failure(error));
    }
  }

  Future<void> _fail(_VoiceRun run, int generation, VoiceFailure failure) async {
    if (!_current(run, generation)) return;
    run.cancelled = true;
    _deadline?.cancel();
    _publish(VoicePhase.error, failure: failure);
    await run.dispose();
  }

  VoiceFailure _failure(Object error) => error is VoiceException ? error.failure : VoiceFailure.microphone;
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

  Future<void> stopMicrophone() async {
    final subscription = audio;
    audio = null;
    await subscription?.cancel();
    await microphone.stop();
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    cancelled = true;
    await speechEvents?.cancel();
    await outputEvents?.cancel();
    for (final cleanup in <Future<void> Function()>[
      stopMicrophone, output.stopSpeaking, speech.dispose, microphone.dispose, output.dispose,
    ]) {
      try { await cleanup(); } catch (_) { /* Continue releasing other resources. */ }
    }
  }
}
