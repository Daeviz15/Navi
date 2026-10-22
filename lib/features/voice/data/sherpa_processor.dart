import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/voice_types.dart';

/// Runs only in the speech isolate. Also usable by the native validation tool.
class SherpaProcessor {
  SherpaProcessor._(this._spotter, this._recognizer, this.emit) {
    _keywordStream = _spotter.createStream();
  }

  static const sampleRate = 16000;
  static const preRollSamples = 24000;
  final sherpa.KeywordSpotter _spotter;
  final sherpa.OnlineRecognizer _recognizer;
  final void Function(SpeechEvent) emit;
  late sherpa.OnlineStream _keywordStream;
  sherpa.OnlineStream? _utteranceStream;
  final _recent = Queue<Float32List>();
  int _recentSamples = 0;
  int _utteranceSamples = 0;
  int? _oddByte;
  String _lastPartial = '';
  SpeechMode _mode = SpeechMode.muted;

  static Future<SherpaProcessor> create(String directory, void Function(SpeechEvent) emit,
      {String? libraryPath}) async {
    final manifest = jsonDecode(await File('$directory/manifest.json').readAsString()) as Map<String, dynamic>;
    for (final entry in (manifest['files'] as Map<String, dynamic>).entries) {
      final digest = await sha256.bind(File('$directory/${entry.key}').openRead()).first;
      if (digest.toString() != (entry.value as Map<String, dynamic>)['sha256']) {
        throw const VoiceException(VoiceFailure.model);
      }
    }
    await sherpa.initBindingsAsync(libraryPath);
    final model = sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: '$directory/encoder.int8.onnx',
        decoder: '$directory/decoder.int8.onnx',
        joiner: '$directory/joiner.int8.onnx'),
      tokens: '$directory/tokens.txt', numThreads: 1, debug: false,
    );
    final spotter = sherpa.KeywordSpotter(sherpa.KeywordSpotterConfig(
      model: model, keywordsFile: '$directory/keywords.txt',
      keywordsThreshold: .35, keywordsScore: 1.2,
    ));
    try {
      // The upstream wake model is a small English transducer ASR model.
      // It is decoded as normal ASR only during the active command window.
      final recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
        model: model, enableEndpoint: true,
        rule1MinTrailingSilence: 2.4, rule2MinTrailingSilence: 1.0,
        rule3MinUtteranceLength: 12,
      ));
      return SherpaProcessor._(spotter, recognizer, emit);
    } catch (_) {
      spotter.free();
      rethrow;
    }
  }

  void setMode(SpeechMode mode) {
    _mode = mode;
    _oddByte = null;
    _recent.clear();
    _recentSamples = 0;
    _utteranceStream?.free();
    _utteranceStream = null;
    _utteranceSamples = 0;
    _lastPartial = '';
    _keywordStream.free();
    _keywordStream = _spotter.createStream();
    if (mode == SpeechMode.listening) _utteranceStream = _recognizer.createStream();
  }

  void acceptPcm(Uint8List bytes) {
    if (_mode == SpeechMode.muted || bytes.isEmpty) return;
    // Retain an odd trailing byte instead of assuming native chunk alignment.
    final input = _oddByte == null ? bytes : Uint8List.fromList([_oddByte!, ...bytes]);
    _oddByte = input.length.isOdd ? input.last : null;
    final samples = Float32List(input.length ~/ 2);
    final data = ByteData.sublistView(input);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    acceptSamples(samples);
  }

  void acceptSamples(Float32List samples) {
    if (_mode == SpeechMode.muted) return;
    if (_mode == SpeechMode.wake) {
      // Fixed 1.5 s upper bound, including for unexpectedly large chunks.
      final retained = samples.length > preRollSamples
          ? Float32List.fromList(samples.sublist(samples.length - preRollSamples))
          : samples;
      _recent.add(retained);
      _recentSamples += retained.length;
      while (_recentSamples > preRollSamples && _recent.isNotEmpty) {
        final first = _recent.removeFirst();
        final excess = _recentSamples - preRollSamples;
        if (first.length > excess) {
          _recent.addFirst(Float32List.fromList(first.sublist(excess)));
          _recentSamples -= excess;
        } else {
          _recentSamples -= first.length;
        }
      }
      _keywordStream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      while (_spotter.isReady(_keywordStream)) {
        _spotter.decode(_keywordStream);
        final keyword = _spotter.getResult(_keywordStream).keyword;
        if (keyword.isNotEmpty) {
          _mode = SpeechMode.listening;
          _utteranceStream = _recognizer.createStream();
          for (final audio in _recent) {
            _utteranceStream!.acceptWaveform(samples: audio, sampleRate: sampleRate);
            _utteranceSamples += audio.length;
          }
          _recent.clear();
          _recentSamples = 0;
          emit(WakeDetected(keyword));
          _decodeUtterance();
          break;
        }
      }
    } else {
      _utteranceStream!.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _utteranceSamples += samples.length;
      _decodeUtterance();
    }
  }

  void _decodeUtterance() {
    final stream = _utteranceStream!;
    while (_recognizer.isReady(stream)) { _recognizer.decode(stream); }
    final text = _recognizer.getResult(stream).text.trim();
    if (text != _lastPartial) {
      _lastPartial = text;
      emit(TranscriptChanged(text));
    }
    if (_recognizer.isEndpoint(stream) || _utteranceSamples >= sampleRate * 12) {
      _mode = SpeechMode.muted;
      emit(UtteranceEnded(text));
    }
  }

  void dispose() {
    _utteranceStream?.free();
    _keywordStream.free();
    _spotter.free();
    _recognizer.free();
  }
}
