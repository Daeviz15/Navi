import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NaviPage extends StatelessWidget {
  const NaviPage({
    super.key,
    required this.child,
    this.title,
    this.step,
    this.onBack,
  });

  final Widget child;
  final String? title;
  final String? step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back_rounded, size: 19),
          onPressed: onBack ?? () => context.go('/'),
        ),
        title: Text(title ?? 'Your journey'),
        actions: [
          if (step != null)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Center(
                child: Text(
                  step!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
