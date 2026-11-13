import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/domain/journey_identity.dart';
import '../../navigation/domain/destination_selection.dart';
import '../data/android_voice_output.dart';
import '../data/pcm_audio_levels.dart';
import '../domain/local_command_router.dart';
import '../domain/destination_confirmation_policy.dart';
import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import '../domain/trip_conversation_progress.dart';
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
  static const audioMeterWindowSamples = 800; // 50 ms at 16 kHz mono PCM16.
  final _commands = const LocalCommandRouter();
  final _destinationConfirmation = const DestinationConfirmationPolicy();
  DestinationReadback? _destinationReadback;
  final _audioMeter = PcmAudioMeter(windowSamples: audioMeterWindowSamples);
  final _audioLevel = ValueNotifier<double>(0.0);
  late VoiceServices _services;
  _VoiceRun? _run;
  _GuidanceOutput? _guidance;
  DestinationSearchToken? _guidanceToken;
  JourneyIdentity? _lastGuidedIntent;
  bool _showingGuidance = false;
  Future<void> _operations = Future.value();
  Timer? _deadline;
  Timer? _startupDeadline;
  int _generation = 0;
  int _runGeneration = -1;
  int _utteranceId = 0;
  int _destinationRevision = 0;
  int _checklistRevision = 0;
  int _tripChangeRevision = 0;
  int _routeLaunchRevision = 0;
  int _endTripRevision = 0;
  bool _enabled = false;
  final _visibleSurfaces = <String>{};
  bool _foreground = true;
  bool _disposed = false;
  bool _isTransitActive = false;
  bool _pendingRouteLaunch = false;
  JourneyTransitContext _transitContext = const JourneyTransitContext();
  TripConversationProgress _conversation = const TripConversationProgress();
  bool _isCasual = false;
  String _rawTranscript = '';
  String _reply = '';
  String? _destination;
  String? _purposeSummary;
  Stopwatch? _responseClock;
  List<String> _checklist = const <String>[];

  ValueListenable<double> get audioLevel => _audioLevel;

  bool get _surfaceVisible => _visibleSurfaces.isNotEmpty;
  bool get _shouldRun =>
      _enabled && _surfaceVisible && _foreground && !_disposed;

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
      final guidance = _guidance;
      _guidance = null;
      if (guidance != null) unawaited(guidance.dispose());
    });
    return const VoiceSessionState();
  }

  Future<void> _setEnabled(
    bool enabled, {
    bool requestPermission = false,
  }) async {
    if (_disposed) return;
    if (enabled && !_enabled) {
      _showingGuidance = false;
      // A new tap can continue discussing the current destination, but an old
      // purpose must never make a fresh conversation immediately complete.
      _conversation = TripConversationProgress(destination: _destination);
      _pendingRouteLaunch = false;
      _rawTranscript = '';
      _reply = '';
    } else if (!enabled && _pendingRouteLaunch && !_conversation.complete) {
      _pendingRouteLaunch = false;
      final reasoner = _services.reasoner;
      if (_isTransitActive && reasoner is ConversationAwareReasoner) {
        (reasoner as ConversationAwareReasoner).updateTransitContext(
          _transitContext,
          resetPendingSwitch: true,
        );
      }
    }
    _enabled = enabled;
    _invalidate();
    _publish(
      enabled
          ? (_shouldRun ? VoicePhase.preparing : VoicePhase.suspended)
          : VoicePhase.off,
    );
    await _reconcile(requestPermission: requestPermission);
  }

  /// Syncs live trip telemetry so Navi adapts cleanly between idle planning
  /// mode and ongoing in-transit guidance.
  void updateTransitContext(
    JourneyTransitContext context, {
    bool preserveConversation = false,
  }) {
    if (_disposed) return;
    final identityChanged = context.identity != _transitContext.identity;
    final hasConversation =
        _transitContext.identity != null ||
        _enabled ||
        _run != null ||
        _destination != null ||
        _reply.isNotEmpty;
    _transitContext = context;
    _isTransitActive = context.isActive;
    if (_showingGuidance &&
        (!context.isActive ||
            identityChanged ||
            context.confirmedPlaceName != null ||
            context.destinationSuggestions?.places.isNotEmpty != true ||
            (_guidanceToken != null &&
                _guidanceToken != context.destinationSuggestions?.token))) {
      _showingGuidance = false;
      _reply = '';
      _invalidate();
      _publish(VoicePhase.off);
    }
    if (_destinationReadback?.request.token !=
        context.destinationSuggestions?.token) {
      _destinationReadback = null;
    }
    if (identityChanged && hasConversation && !preserveConversation) {
      // An external trip/mode change invalidates a reply already in flight.
      // Changes accepted from this conversation are acknowledged by the bridge
      // so Navi can finish the answer and continue collecting its purpose.
      _enabled = false;
      _pendingRouteLaunch = false;
      _destination = context.destination;
      _purposeSummary = context.purposeSummary;
      _isCasual = context.isCasual;
      _checklist = context.checklist;
      _rawTranscript = '';
      _reply = '';
      _conversation = const TripConversationProgress();
      final reasoner = _services.reasoner;
      if (reasoner is ConversationAwareReasoner) {
        (reasoner as ConversationAwareReasoner).clearTripContext();
      }
      _invalidate();
      _publish(VoicePhase.off);
      unawaited(_reconcile(requestPermission: false));
    }
    final dest = context.destination?.trim();
    if (!_enabled &&
        context.isActive &&
        dest != null &&
        dest.isNotEmpty &&
        _destination?.toLowerCase() != dest.toLowerCase()) {
      _destination = dest;
    }
    final reasoner = _services.reasoner;
    if (reasoner is ConversationAwareReasoner) {
      (reasoner as ConversationAwareReasoner).updateTransitContext(context);
    }
  }

  /// Clears trip state and agent conversation history when ending a trip.
  Future<void> clearActiveTrip() async {
    if (_disposed) return;
    _isTransitActive = false;
    _pendingRouteLaunch = false;
    _transitContext = JourneyTransitContext(identity: _transitContext.identity);
    _destination = null;
    _purposeSummary = null;
    _isCasual = false;
    _checklist = const <String>[];
    _rawTranscript = '';
    _reply = '';
    _conversation = const TripConversationProgress();
    _showingGuidance = false;
    final reasoner = _services.reasoner;
    if (reasoner is ConversationAwareReasoner) {
      (reasoner as ConversationAwareReasoner).clearTripContext();
    }
    await _setEnabled(false);
  }

  /// The only user activation path. A second tap always cancels the entire
  /// session, including capture, pending replies and speech playback.
  Future<void> toggleConversation({String? destination}) async {
    if (_disposed) return;
    if (!_enabled && _isTransitActive) {
      final reasoner = _services.reasoner;
      if (reasoner is ConversationAwareReasoner) {
        (reasoner as ConversationAwareReasoner).updateTransitContext(
          _transitContext,
          resetPendingSwitch: true,
        );
      }
    } else if (!_enabled &&
        destination != null &&
        destination.trim().isNotEmpty) {
      final target = destination.trim();
      if (_destination?.toLowerCase() != target.toLowerCase()) {
        _destination = target;
        _purposeSummary = null;
        _isCasual = false;
        _checklist = const [];
      }
      final reasoner = _services.reasoner;
      if (reasoner is ConversationAwareReasoner) {
        (reasoner as ConversationAwareReasoner).setDestinationContext(target);
      }
    }
    await _setEnabled(!_enabled, requestPermission: !_enabled);
  }

  /// A speech-only orientation, serialized with conversation output. This never
  /// constructs a microphone or recognizer, requests permission, or starts a
  /// follow-up. A tap cancels it before starting the normal conversation path.
  Future<void> announceDestinationChoices(DestinationSearchToken token) {
    if (_disposed ||
        _enabled ||
        !_transitContext.isActive ||
        !_foreground ||
        !_visibleSurfaces.contains('journey') ||
        token != _transitContext.destinationSuggestions?.token ||
        token.journey != _transitContext.identity ||
        _transitContext.confirmedPlaceName != null ||
        _transitContext.destinationSuggestions!.places.isEmpty ||
        _lastGuidedIntent == token.journey) {
      return Future.value();
    }
    _lastGuidedIntent = token.journey;
    _invalidate();
    _guidanceToken = token;
    _showingGuidance = true;
    final generation = _generation;
    bool current() =>
        !_disposed && generation == _generation && _guidanceToken == token;
    _rawTranscript = '';
    _reply =
        'Let’s confirm the exact destination. Choose an address below, '
        'or tap me beside the choices and say an option number.';
    _publish(VoicePhase.preparingReply);
    _operations = _operations
        .then((_) async {
          final previous = _run;
          _run = null;
          await previous?.dispose();
          await _guidance?.dispose();
          if (!current()) return;
          final guidance = _GuidanceOutput(_services.output());
          _guidance = guidance;
          final id = ++_utteranceId;
          guidance.events = guidance.output.events.listen((event) {
            if (!current() || event.id != id) return;
            if (event.type == OutputEventType.started) {
              _publish(VoicePhase.speaking);
            } else if (event.type == OutputEventType.failed ||
                event.type == OutputEventType.cancelled) {
              unawaited(guidance.dispose());
            }
          });
          try {
            await guidance.whileActive(
              guidance.output.initialize().timeout(const Duration(seconds: 10)),
            );
            if (!current()) return;
            await guidance.whileActive(
              guidance.output
                  .speak(_reply, id: id)
                  .timeout(const Duration(seconds: 30)),
            );
          } catch (_) {
            // The visible instruction remains usable when speech is unavailable.
          } finally {
            await guidance.dispose();
            if (identical(_guidance, guidance)) _guidance = null;
            if (current()) {
              _guidanceToken = null;
              _publish(VoicePhase.off);
            }
          }
        })
        .catchError((Object _) {
          if (current()) {
            _guidanceToken = null;
            _publish(VoicePhase.off);
          }
        });
    return _operations;
  }

  /// Scheduled outside widget build/disposal so providers are never mutated
  /// synchronously while the widget tree is being assembled.
  void setHomeVisible(bool visible) => setSurfaceVisible('home', visible);

  void setSurfaceVisible(String owner, bool visible) {
    if (_disposed) return;
    final wasVisible = _surfaceVisible;
    if (visible) {
      _visibleSurfaces.add(owner);
    } else {
      _visibleSurfaces.remove(owner);
    }
    final dismissGuidance = owner == 'journey' && !visible && _showingGuidance;
    if (dismissGuidance) {
      _showingGuidance = false;
      _reply = '';
    }
    if (wasVisible == _surfaceVisible && !dismissGuidance) return;
    _invalidate();
    Future.microtask(() {
      if (!_disposed) unawaited(_reconcile(requestPermission: false));
    });
  }

  void setForeground(bool foreground, {bool transient = false}) {
    if (_disposed) return;
    // A transient inactive state includes the microphone permission dialog.
    // True backgrounding ends capture and requires a fresh tap after return.
    if (!foreground && transient) return;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) _enabled = false;
    _invalidate();
    unawaited(_reconcile(requestPermission: false));
  }

  void suspendForNavigation() => setHomeVisible(false);

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
    _guidanceToken = null;
    final guidance = _guidance;
    if (guidance != null) unawaited(guidance.dispose());
    _destinationReadback = null;
    _generation++;
    final reasoner = _services.reasoner;
    if (reasoner is ConversationAwareReasoner) {
      (reasoner as ConversationAwareReasoner).cancelPendingReply();
    }
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
          // Visibility changes can enqueue the same start.
          // A failed run waits for an explicit retry rather than starting twice.
          if (_run != null && _runGeneration == generation) return;
          final previous = _run;
          _run = null;
          await previous?.dispose();
          await _guidance?.dispose();
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
            // delay opening capture after a tap.
            run.prepareOutput();
            await run.whileActive(run.speech.initialize());
            if (!_current(run, generation)) return;
            await _listen(run, generation);
            if (_current(run, generation)) {
              _startupDeadline?.cancel();
              developer.log(
                'Conversation ready in ${startup.elapsedMilliseconds}ms',
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
    final cleanedTranscript = _commands.removeWakePhrase(_rawTranscript);
    final effectiveTranscript = cleanedTranscript.isEmpty
        ? _rawTranscript.trim()
        : cleanedTranscript;
    state = VoiceSessionState(
      journeyIdentity: _transitContext.identity,
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
      tripChangeRevision: _tripChangeRevision,
      routeLaunchRevision: _routeLaunchRevision,
      endTripRevision: _endTripRevision,
    );
  }

  Future<void> _listen(_VoiceRun run, int generation) async {
    if (!_current(run, generation)) return;
    _resetAudioLevel();
    await run.stopMicrophone();
    if (!_current(run, generation)) return;
    run.speech.setMode(SpeechMode.listening);
    final audio = await run.whileActive(run.microphone.start());
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
    _publish(VoicePhase.listening);
    _deadline?.cancel();
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
      case WakeDetected():
        // Legacy engines cannot activate or control a tap-only conversation.
        return;
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
        if (text.trim().isEmpty) {
          unawaited(
            _listen(run, generation).catchError(
              (Object error) => _fail(run, generation, _failure(error)),
            ),
          );
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
    final reasoner = _services.reasoner;
    LocalReply? response;
    var destinationTurn = _destinationConfirmation.resolve(
      text,
      suggestions: _transitContext.destinationSuggestions,
      spokenPrompt: _destinationReadback,
    );
    // A "yes" after an unrelated answer must not confirm an older address.
    // Only a newly completed readback can arm the next confirmation turn.
    _destinationReadback = null;
    final selectionRequest = destinationTurn?.request;
    if (selectionRequest != null) {
      final accepted = destinationTurn!.reject
          ? _services.destinations?.reject(selectionRequest) ?? false
          : _services.destinations?.confirm(selectionRequest) ?? false;
      if (!accepted) {
        destinationTurn = const DestinationVoiceTurn(
          'Those place matches are no longer available. Choose the current address on the map.',
        );
      }
    }
    if (destinationTurn != null) {
      response = LocalReply(
        LocalIntent.clarify,
        destinationTurn.text,
        followUp: destinationTurn.followUp,
      );
      _reply = response.text;
    } else if (reasoner is LocalCommandRouter) {
      response = reasoner.route(text);
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
            reasoner.resolve(text, wakeDetected: false),
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
      await run.whileActive(run.output.speak(resolved.text, id: id));
      if (!_current(run, generation)) return;
      if (destinationTurn != null) {
        final prompt = destinationTurn.prompt;
        _destinationReadback =
            prompt?.request.token ==
                _transitContext.destinationSuggestions?.token
            ? prompt
            : null;
        if (resolved.followUp) {
          await _listen(run, generation);
        } else {
          await _setEnabled(false);
        }
        return;
      }
      if (resolved.endTrip) {
        _endTripRevision++;
        await _setEnabled(false);
      } else if (_pendingRouteLaunch && _conversation.complete) {
        _pendingRouteLaunch = false;
        _routeLaunchRevision++;
        await _setEnabled(false);
      } else if (_isTransitActive && !_pendingRouteLaunch) {
        if (resolved.intent == LocalIntent.sleep || !resolved.followUp) {
          await _setEnabled(false);
        } else {
          await _listen(run, generation);
        }
      } else if (_conversation.complete) {
        await _setEnabled(false);
      } else {
        await _listen(run, generation);
      }
    } catch (error) {
      await _fail(run, generation, _failure(error));
    }
  }

  void _applyReply(LocalReply response) {
    if (response.endTrip) {
      _reply = response.text;
      return;
    }
    if (response.changeTrip && response.destination != null) {
      _pendingRouteLaunch = true;
      _destination = response.destination!.trim();
      _destinationRevision++;
      _tripChangeRevision++;
      _purposeSummary = response.purposeSummary;
      _isCasual = response.isCasual;
      _checklist = response.isCasual
          ? const <String>[]
          : List<String>.unmodifiable(response.checklist);
      _checklistRevision++;
      _conversation = TripConversationProgress(
        destination: _destination,
        purpose: response.purposeSummary,
      );
      _reply = response.text;
      return;
    }
    if (_isTransitActive && !_pendingRouteLaunch) {
      _reply = response.text;
      return;
    }
    final previousProgress = _conversation;
    _conversation = _conversation.apply(response);
    _reply = response.text;
    if (response.destination != null) {
      final isDifferentDestination =
          _destination?.toLowerCase() != response.destination!.toLowerCase();
      _destination = response.destination;
      _destinationRevision++;
      if (isDifferentDestination) {
        // Purpose can be supplied before the first destination in this session.
        // Preserve that preparation, but never carry it across changed places.
        if (previousProgress.destination != null ||
            previousProgress.purpose == null) {
          _purposeSummary = null;
          _isCasual = false;
          _checklist = const <String>[];
        }
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
    _enabled = false;
    _deadline?.cancel();
    _startupDeadline?.cancel();
    _resetAudioLevel();
    _publish(VoicePhase.error, failure: failure);
    await run.dispose();
  }

  VoiceFailure _failure(Object error) =>
      error is VoiceException ? error.failure : VoiceFailure.microphone;
}

/// Shares the output factory with conversations, but owns no capture resources.
class _GuidanceOutput {
  _GuidanceOutput(this.output);
  final VoiceGateway output;
  StreamSubscription<OutputEvent>? events;
  final _cancelled = Completer<void>();
  Future<void>? _disposing;

  Future<T> whileActive<T>(Future<T> operation) => Future.any<T>([
    operation,
    _cancelled.future.then<T>(
      (_) => throw const VoiceException(VoiceFailure.interrupted),
    ),
  ]);

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    if (!_cancelled.isCompleted) _cancelled.complete();
    await events?.cancel();
    for (final cleanup in [output.stopSpeaking, output.dispose]) {
      try {
        await cleanup();
      } catch (_) {
        // Releasing one resource must not prevent releasing the next.
      }
    }
  }
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
