import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'sherpa_processor.dart';
import 'voice_model_assets.dart';

/// Bounded, single-consumer bridge. FFI never runs on the Flutter UI isolate.
class SherpaSpeechEngine implements SpeechEngine {
  SherpaSpeechEngine({VoiceModelAssets? assets}) : _assets = assets ?? VoiceModelAssets();

  final VoiceModelAssets _assets;
  final _events = StreamController<SpeechEvent>.broadcast();
  final _queue = Queue<Uint8List>();
  int _queuedBytes = 0;
  int _epoch = 0;
  bool _busy = false;
  bool _disposed = false;
  SpeechMode _mode = SpeechMode.muted;
  Isolate? _isolate;
  ReceivePort? _receive;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _send;
  Completer<void>? _initializing;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<void> initialize() {
    if (_disposed) throw StateError('Speech engine disposed');
    if (_initializing != null) return _initializing!.future;
    final ready = _initializing = Completer<void>();
    unawaited(_start(ready));
    return ready.future;
  }

  Future<void> _start(Completer<void> ready) async {
    try {
      final directory = await _assets.prepare();
      if (_disposed) throw StateError('Speech engine disposed');
      final receive = _receive = ReceivePort();
      _subscription = receive.listen((dynamic message) {
        if (_disposed) return;
        if (message is SendPort) {
          _send = message;
          if (!ready.isCompleted) ready.complete();
          return;
        }
        if (message is! Map) return;
        if (message['ack'] == true) {
          _busy = false;
          _sendNext();
        } else if (message['event'] is SpeechEvent && message['epoch'] == _epoch) {
          _events.add(message['event'] as SpeechEvent);
        } else if (message['failed'] == true) {
          if (!ready.isCompleted) ready.completeError(const VoiceException(VoiceFailure.model));
          _events.add(const SpeechFailed(VoiceFailure.model));
        }
      });
      _isolate = await Isolate.spawn<List<Object>>(_speechWorker, [receive.sendPort, directory],
        debugName: 'navi-local-speech', onError: receive.sendPort,
        onExit: receive.sendPort, errorsAreFatal: true);
      await ready.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      if (!ready.isCompleted) ready.completeError(const VoiceException(VoiceFailure.model));
    }
  }

  @override
  void setMode(SpeechMode mode) {
    _mode = mode;
    _epoch++;
    _queue.clear();
    _queuedBytes = 0;
    _send?.send({'mode': mode.index, 'epoch': _epoch});
  }

  @override
  void addAudio(Uint8List bytes) {
    if (_disposed || _send == null || _mode == SpeechMode.muted) return;
    // Two seconds is a hard bound. Fail visibly instead of silently dropping
    // words or allowing a native event stream to grow without limit.
    if (_queuedBytes + bytes.length > 64000) {
      setMode(SpeechMode.muted);
      _events.add(const SpeechFailed(VoiceFailure.processingOverrun));
      return;
    }
    _queue.add(Uint8List.fromList(bytes));
    _queuedBytes += bytes.length;
    _sendNext();
  }

  void _sendNext() {
    if (_busy || _disposed || _queue.isEmpty || _send == null) return;
    final bytes = _queue.removeFirst();
    _queuedBytes -= bytes.length;
    _busy = true;
    _send!.send({'audio': TransferableTypedData.fromList([bytes]), 'epoch': _epoch});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _send?.send({'dispose': true});
    // The isolate gets a brief opportunity to free its native streams/models.
    final isolate = _isolate;
    if (isolate != null) Timer(const Duration(seconds: 1), () => isolate.kill());
    await _subscription?.cancel();
    _receive?.close();
    await _events.close();
  }
}

void _speechWorker(List<Object> arguments) async {
  final parent = arguments[0] as SendPort;
  final directory = arguments[1] as String;
  var epoch = 0;
  SherpaProcessor? processor;
  final receive = ReceivePort();
  try {
    processor = await SherpaProcessor.create(directory,
      (event) => parent.send({'epoch': epoch, 'event': event}));
    parent.send(receive.sendPort);
    await for (final dynamic message in receive) {
      if (message is! Map) continue;
      if (message['dispose'] == true) break;
      if (message['mode'] is int) {
        epoch = message['epoch'] as int;
        processor.setMode(SpeechMode.values[message['mode'] as int]);
      } else if (message['audio'] is TransferableTypedData) {
        try {
          if (message['epoch'] == epoch) {
            final audio = (message['audio'] as TransferableTypedData).materialize().asUint8List();
            processor.acceptPcm(audio);
          }
        } catch (_) {
          parent.send({'epoch': epoch, 'event': const SpeechFailed(VoiceFailure.model)});
        } finally {
          parent.send({'ack': true});
        }
      }
    }
  } catch (_) {
    parent.send({'failed': true});
  } finally {
    processor?.dispose();
    receive.close();
  }
}
