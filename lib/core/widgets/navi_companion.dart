import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A single muted preview clip. Behavior selection will be added separately.
class NaviCompanion extends StatefulWidget {
  const NaviCompanion({super.key, this.size = 290});

  final double size;
  static const videoAsset = 'assets/videos/idle/idle_01_sip.mp4';
  static const posterAsset = 'assets/images/navi_idle_poster.jpg';
  static const transparentAnimationAsset = 'assets/animations/idle_01_sip.webp';
  static const transparentPosterAsset =
      'assets/images/navi_idle_transparent.png';

  @override
  State<NaviCompanion> createState() => _NaviCompanionState();
}

class _NaviCompanionState extends State<NaviCompanion>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;
  bool _isLight = false;
  bool _foreground = true;
  bool _visible = true;
  bool _reduceMotion = false;

  bool get _shouldPlay =>
      !_isLight && _foreground && _visible && !_reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.asset(
      NaviCompanion.videoAsset,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        preventsDisplaySleepDuringVideoPlayback: false,
      ),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      await _controller.setVolume(0);
      if (!mounted) return;
      await _controller.setLooping(true);
      if (!mounted) return;
      _controller.addListener(_onVideoChanged);
      setState(() => _ready = true);
      await _syncPlayback();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVideoChanged() {
    if (_controller.value.hasError && !_failed && mounted) {
      setState(() => _failed = true);
    }
  }

  Future<void> _syncPlayback() async {
    if (!_ready || !mounted || _failed) return;
    try {
      if (_shouldPlay) {
        await _controller.play();
      } else {
        await _controller.pause();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _isLight = Theme.of(context).brightness == Brightness.light;
    unawaited(_syncPlayback());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    unawaited(_syncPlayback());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onVideoChanged);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The WebP is made from the same source clip with a connected-background
    // alpha matte, so light mode preserves dark eyes, shoes and the navy cup.
    final video = _isLight
        ? TickerMode(
            enabled: _foreground && _visible && !_reduceMotion,
            child: Image.asset(
              _reduceMotion
                  ? NaviCompanion.transparentPosterAsset
                  : NaviCompanion.transparentAnimationAsset,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => Image.asset(
                NaviCompanion.transparentPosterAsset,
                fit: BoxFit.cover,
              ),
            ),
          )
        : _ready && !_failed
        ? SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          )
        : Image.asset(NaviCompanion.posterAsset, fit: BoxFit.cover);

    return Semantics(
      label: 'Navi, your yellow travel companion, relaxing with a drink',
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.none,
              child: SizedBox(
                width: widget.size * 1.35 * 9 / 16,
                height: widget.size * 1.35,
                child: video,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
