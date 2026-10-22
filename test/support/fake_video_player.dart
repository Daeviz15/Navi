import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:navi/core/widgets/navi_companion.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayer extends VideoPlayerPlatform {
  int _nextId = 0;
  final _streams = <int, StreamController<VideoEvent>>{};
  final playing = <int>{};
  final disposed = <int>{};
  final disposalCompleted = Completer<void>();
  final assets = <String?>[];
  final volumes = <int, double>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    assets.add(options.dataSource.asset);
    final id = ++_nextId;
    _streams[id] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(720, 1280),
        ),
      );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    playing.remove(playerId);
    disposed.add(playerId);
    await _streams.remove(playerId)?.close();
    if (!disposalCompleted.isCompleted) disposalCompleted.complete();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> play(int playerId) async => playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => playing.remove(playerId);

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes[playerId] = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Image.asset(NaviCompanion.posterAsset, fit: BoxFit.cover);
}
