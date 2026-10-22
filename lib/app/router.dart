import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/preparation/presentation/preparation_screen.dart';
import '../features/journey/presentation/route_preview_screen.dart';
// Archived while the app moves to prerecorded character videos.
// import '../features/character/presentation/character_lab_screen.dart';

final GoRouter naviRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/prepare',
      builder: (context, state) => const PreparationScreen(),
    ),
    GoRoute(
      path: '/preview',
      builder: (context, state) => const RoutePreviewScreen(),
    ),
    // GoRoute(
    //   path: '/character-lab',
    //   builder: (context, state) => const CharacterLabScreen(),
    // ),
  ],
);
