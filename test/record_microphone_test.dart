import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/voice/data/record_microphone.dart';
import 'package:record/record.dart';

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'listening waits for real PCM and preserves startup audio until subscribed',
    () async {
      final previous = RecordPlatform.instance;
      final platform = _Record();
      RecordPlatform.instance = platform;
      final mic = RecordMicrophone();
      try {
        var ready = false;
        final pending = mic.start().then((stream) {
          ready = true;
          return stream;
        });
        await flush();
        expect(ready, isFalse);
        expect(platform.config!.autoGain, isTrue);
        expect(platform.config!.noiseSuppress, isTrue);
        expect(platform.config!.echoCancel, isFalse);
        final first = Uint8List.fromList([1, 2, 3, 4]);
        platform.frames.add(first);
        final stream = await pending;
        platform.frames.add(Uint8List.fromList([5, 6]));
        final received = <Uint8List>[];
        final sub = stream.listen(received.add);
        await flush();
        expect(received, [
          first,
          [5, 6],
        ]);
        await mic.stop();
        await sub.cancel();
        expect(platform.stops, 1);
      } finally {
        await mic.dispose();
        await platform.frames.close();
        RecordPlatform.instance = previous;
      }
    },
  );

  testWidgets(
    'a microphone that never delivers PCM times out and releases capture',
    (tester) async {
      final previous = RecordPlatform.instance;
      final platform = _Record();
      RecordPlatform.instance = platform;
      final mic = RecordMicrophone();
      final result = expectLater(mic.start(), throwsA(isA<TimeoutException>()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await result;
      expect(platform.stops, 1);
      await mic.dispose();
      await platform.frames.close();
      RecordPlatform.instance = previous;
    },
  );
}

class _Record extends RecordPlatform {
  final frames = StreamController<Uint8List>.broadcast();
  RecordConfig? config;
  int stops = 0;
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    this.config = config;
    return frames.stream;
  }

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig)? handler,
  ) {}
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<String?> stop(String recorderId) async {
    stops++;
    return null;
  }

  @override
  Future<void> dispose(String recorderId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
