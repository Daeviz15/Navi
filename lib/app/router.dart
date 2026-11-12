import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/journey/presentation/journey_flow_scope.dart';
import '../features/journey/presentation/journey_initialization_screen.dart';
import '../features/journey/presentation/route_preview_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
// Archived while the app moves to prerecorded character videos.
// import '../features/character/presentation/character_lab_screen.dart';

final GoRouter naviRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const SplashScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      ),
    ),
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const HomeScreen(),
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ),
    GoRoute(path: '/prepare', redirect: (context, state) => '/initialize'),
    ShellRoute(
      builder: (context, state, child) => JourneyFlowScope(child: child),
      routes: [
        GoRoute(
          path: '/initialize',
          pageBuilder: (context, state) =>
              _journeyPage(context, state, const JourneyInitializationScreen()),
        ),
        GoRoute(
          path: '/preview',
          pageBuilder: (context, state) =>
              _journeyPage(context, state, const RoutePreviewScreen()),
        ),
      ],
    ),
    // GoRoute(
    //   path: '/character-lab',
    //   builder: (context, state) => const CharacterLabScreen(),
    // ),
  ],
);

CustomTransitionPage<void> _journeyPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 420),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
);
