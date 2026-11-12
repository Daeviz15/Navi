import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'navi_letter_walk_painter.dart';

/// Full-screen animated splash featuring the walking traveler illuminating "NAVI".
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 3200),
    this.autoNavigate = true,
    this.onProceed,
  });

  final Duration duration;
  final bool autoNavigate;
  final VoidCallback? onProceed;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _controller.addListener(() {
      setState(() {});
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.autoNavigate) {
        _proceedToHome();
      }
    });

    // Check if animations are disabled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        if (widget.autoNavigate) {
          _proceedToHome();
        }
      } else {
        _controller.forward();
      }
    });
  }

  void _proceedToHome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    if (widget.onProceed != null) {
      widget.onProceed!();
      return;
    }
    try {
      context.go('/');
    } catch (_) {
      // Safely ignore if no GoRouter is in the widget tree (e.g. isolated unit tests)
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _controller.value;

    // Subtitle opacity fades in between t = 0.86 -> 0.98
    final double subtitleOpacity = ((t - 0.86) / 0.12).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _proceedToHome,
        child: Stack(
          children: [
            // Ambient subtle background gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      const Color(0xFF131A29).withValues(alpha: 0.65),
                      const Color(0xFF07090E),
                    ],
                  ),
                ),
              ),
            ),

            // Main custom painted animated word & walking companion
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 320,
                      height: 180,
                      child: CustomPaint(
                        painter: NaviLetterWalkPainter(
                          progress: t,
                          primaryColor: const Color(0xFFF59E0B),
                          accentColor: const Color(0xFFFDE68A),
                          dimColor: const Color(0x1AFFFFFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Tagline reveal
                    Opacity(
                      opacity: subtitleOpacity,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - subtitleOpacity)),
                        child: Text(
                          'YOUR PURPOSE-AWARE COMPANION',
                          style: TextStyle(
                            fontFamily: 'Syne',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3.2,
                            color: const Color(0xFFFBBF24).withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top-right subtle "Skip" pill
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              right: 20,
              child: AnimatedOpacity(
                opacity: t > 0.15 ? 0.75 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: TextButton(
                  onPressed: _proceedToHome,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  child: const Text('SKIP'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
