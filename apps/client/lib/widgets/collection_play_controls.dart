import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// Collection transport: shuffle at the left, a centered Play pill, and an
/// optional collection action at the right. Both side slots have equal width.
class CollectionPlayControls extends StatelessWidget {
  const CollectionPlayControls({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    this.trailing,
  });
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Row(
          children: [
            GlassSurface(
              radius: 26,
              child: IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                tooltip: 'Shuffle',
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onSurface,
                  foregroundColor: scheme.surface,
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  shape: const StadiumBorder(),
                ),
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              height: 48,
              child: trailing == null
                  ? null
                  : GlassSurface(radius: 26, child: trailing!),
            ),
          ],
        ),
      ),
    );
  }
}
