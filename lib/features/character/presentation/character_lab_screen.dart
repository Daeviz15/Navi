// Archived character experiment. Retained for reference; not part of the active app.
// The home screen now uses the prerecorded Navi video preview.
//
// import 'dart:async';
// import 'package:flutter/material.dart';
//
// /// Swap the portrait file at this path without changing the state machine.
// /// Facial blinking/lip-sync require additional matching facial assets.
// class CharacterLabScreen extends StatefulWidget {
//   const CharacterLabScreen({super.key});
//
//   @override
//   State<CharacterLabScreen> createState() => _CharacterLabScreenState();
// }
//
// enum NaviAvatarState { idle, listening, thinking, speaking }
//
// class _CharacterLabScreenState extends State<CharacterLabScreen>
//     with SingleTickerProviderStateMixin {
//   static const portraitPath = 'assets/avatars/navi_base.png';
//   NaviAvatarState state = NaviAvatarState.idle;
//   late final AnimationController pulse;
//   Timer? autoIdle;
//
//   @override
//   void initState() {
//     super.initState();
//     pulse = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 2400),
//     )..repeat(reverse: true);
//   }
//
//   void setAvatarState(NaviAvatarState next) {
//     autoIdle?.cancel();
//     setState(() => state = next);
//   }
//
//   @override
//   void dispose() {
//     autoIdle?.cancel();
//     pulse.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final scheme = Theme.of(context).colorScheme;
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     const blue = Color(0xFF6EA8FF);
//     final stage = dark ? const Color(0xFF101C33) : const Color(0xFFEAF0FA);
//     final captions = {
//       NaviAvatarState.idle: 'Ready whenever you are.',
//       NaviAvatarState.listening: 'I’m listening…',
//       NaviAvatarState.thinking: 'Working on that…',
//       NaviAvatarState.speaking: 'Navi is speaking (visual preview only).',
//     };
//     final icons = {
//       NaviAvatarState.idle: Icons.waving_hand_outlined,
//       NaviAvatarState.listening: Icons.mic_none_rounded,
//       NaviAvatarState.thinking: Icons.auto_awesome_outlined,
//       NaviAvatarState.speaking: Icons.graphic_eq_rounded,
//     };
//
//     return Scaffold(
//       appBar: AppBar(title: const Text('NAVI · Avatar Lab')),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
//           child: Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 510),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Text('NAVI · 2D AVATAR PROTOTYPE',
//                       style: TextStyle(fontSize: 11, letterSpacing: 1.5,
//                           fontWeight: FontWeight.w700, color: blue)),
//                   const SizedBox(height: 12),
//                   Text('Meet Navi.', style: Theme.of(context).textTheme.headlineMedium),
//                   const SizedBox(height: 8),
//                   Text('A lightweight, replaceable portrait with assistant states. '
//                       'Facial blinking and lip-sync are not implemented yet.',
//                       style: TextStyle(color: scheme.onSurfaceVariant)),
//                   const SizedBox(height: 20),
//                   Container(
//                     height: 360,
//                     width: double.infinity,
//                     clipBehavior: Clip.antiAlias,
//                     decoration: BoxDecoration(
//                       color: stage,
//                       borderRadius: BorderRadius.circular(28),
//                       border: Border.all(color: scheme.outlineVariant),
//                     ),
//                     child: AnimatedBuilder(
//                       animation: pulse,
//                       builder: (context, child) {
//                         final level = pulse.value;
//                         final alive = state != NaviAvatarState.idle;
//                         return Stack(
//                           alignment: Alignment.center,
//                           children: [
//                             Container(
//                               width: 260 + (alive ? level * 10 : level * 4),
//                               height: 260 + (alive ? level * 10 : level * 4),
//                               decoration: BoxDecoration(
//                                 shape: BoxShape.circle,
//                                 boxShadow: [BoxShadow(
//                                   color: blue.withValues(alpha: alive ? .16 + level * .12 : .09),
//                                   blurRadius: 45 + level * 18,
//                                   spreadRadius: level * 12,
//                                 )],
//                               ),
//                             ),
//                             Transform.translate(
//                               offset: Offset(0, -8 + (level - .5) * 3),
//                               child: Transform.scale(
//                                 scale: 0.90 + level * .008,
//                                 child: Image.asset(
//                                   portraitPath,
//                                   height: 295,
//                                   fit: BoxFit.contain,
//                                   filterQuality: FilterQuality.medium,
//                                   errorBuilder: (_, error, stack) =>
//                                       const Text('Avatar missing. Check pubspec.yaml assets.'),
//                                 ),
//                               ),
//                             ),
//                             Positioned(
//                               bottom: 16,
//                               child: Row(
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   Icon(icons[state], color: blue, size: 16),
//                                   const SizedBox(width: 8),
//                                   Text(captions[state]!, style: TextStyle(
//                                     color: scheme.onSurface, fontSize: 12)),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         );
//                       },
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                   Text('PREVIEW ASSISTANT STATES',
//                       style: TextStyle(fontSize: 11, letterSpacing: 1.2,
//                           fontWeight: FontWeight.w700,
//                           color: scheme.onSurfaceVariant)),
//                   const SizedBox(height: 12),
//                   Wrap(
//                     spacing: 8,
//                     runSpacing: 8,
//                     children: NaviAvatarState.values.map((value) {
//                       return ChoiceChip(
//                         label: Text(value.name[0].toUpperCase() + value.name.substring(1)),
//                         selected: value == state,
//                         onSelected: (_) => setAvatarState(value),
//                       );
//                     }).toList(),
//                   ),
//                   const SizedBox(height: 20),
//                   Text('The buttons simulate assistant states; they do not '
//                       'activate the microphone or play audio. The portrait can be '
//                       'replaced by overwriting $portraitPath. New facial frames '
//                       'will need to match the replacement portrait.',
//                       style: TextStyle(fontSize: 12,
//                           height: 1.5, color: scheme.onSurfaceVariant)),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
