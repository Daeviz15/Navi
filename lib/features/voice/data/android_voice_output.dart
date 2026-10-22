import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';

/// Android's installed offline TTS, with native utterance IDs end to end.
class AndroidVoiceOutput implements VoiceGateway {
  static const _channel = MethodChannel('navi/voice_output');
  final _events = StreamController<OutputEvent>.broadcast();
  Completer<void>? _completion;
  int? _activeId;
  bool _ready = false;

  @override
  Stream<OutputEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_ready) return;
    if (!Platform.isAndroid) throw const VoiceException(VoiceFailure.unavailable);
    _channel.setMethodCallHandler(_onEvent);
    try {
      await _channel.invokeMethod<void>('initialize').timeout(const Duration(seconds: 15));
      _ready = true;
    } on PlatformException catch (error) {
      throw VoiceException(error.code == 'offline_voice_missing'
          ? VoiceFailure.offlineVoiceMissing : VoiceFailure.output);
    }
  }

  Future<void> _onEvent(MethodCall call) async {
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    final id = int.tryParse(arguments['id'].toString());
    if (id == null || id != _activeId) return;
    final type = switch (call.method) {
      'started' => OutputEventType.started,
      'completed' => OutputEventType.completed,
      'cancelled' => OutputEventType.cancelled,
      _ => OutputEventType.failed,
    };
    _events.add(OutputEvent(id, type));
    if (type != OutputEventType.started) {
      final completion = _completion;
      _completion = null;
      _activeId = null;
      if (completion != null && !completion.isCompleted) {
        if (type == OutputEventType.failed) {
          completion.completeError(const VoiceException(VoiceFailure.output));
        } else {
          completion.complete();
        }
      }
    }
  }

  @override
  Future<void> speak(String message, {required int id}) async {
    if (!_ready) await initialize();
    await stopSpeaking();
    final completion = _completion = Completer<void>();
    _activeId = id;
    // Attach the error listener before dispatching to the platform.
    final finished = completion.future.timeout(const Duration(seconds: 30));
    try {
      await _channel.invokeMethod<void>('speak', {'id': '$id', 'text': message});
      await finished;
    } catch (_) {
      if (_activeId == id) await stopSpeaking();
      throw const VoiceException(VoiceFailure.output);
    }
  }

  @override
  Future<void> stopSpeaking() async {
    _activeId = null;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) completion.complete();
    if (_ready) await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> dispose() async {
    await stopSpeaking();
    if (_ready) await _channel.invokeMethod<void>('dispose');
    _channel.setMethodCallHandler(null);
    await _events.close();
    _ready = false;
  }
}
