import 'package:flutter/material.dart';

import '../../services/startup_stage.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({
    super.key,
    required this.stage,
    this.takingLonger = false,
    this.onRetry,
  });

  final StartupStage stage;
  final bool takingLonger;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.graphic_eq,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Hyperstream',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 24),
                if (onRetry == null) const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  onRetry == null
                      ? stage.label
                      : 'Could not finish: ${stage.label.toLowerCase()}.',
                  textAlign: TextAlign.center,
                ),
                if (takingLonger && onRetry == null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'This is taking longer than expected. Close and reopen the app. If it happens again, report the step shown above.',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
