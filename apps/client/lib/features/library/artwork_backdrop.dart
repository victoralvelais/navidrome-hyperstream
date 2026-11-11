import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';
import '../../widgets/glass_surface.dart';

/// A quiet wash from the real cover, with a scrim keeping text contrast stable.
class ArtworkBackdrop extends StatefulWidget {
  const ArtworkBackdrop({
    super.key,
    required this.client,
    required this.coverArt,
    required this.child,
    this.immersive = true,
  });
  final NavidromeClient client;
  final String? coverArt;
  final Widget child;
  final bool immersive;
  @override
  State<ArtworkBackdrop> createState() => _ArtworkBackdropState();
}

class _ArtworkBackdropState extends State<ArtworkBackdrop> {
  Future<Uint8List?>? _artwork;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtworkBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverArt != widget.coverArt ||
        oldWidget.client != widget.client) {
      _load();
    }
  }

  void _load() {
    // Only bytes enter Image.memory; authenticated URLs never reach diagnostics.
    _artwork = widget.coverArt == null ? null : _read();
  }

  Future<Uint8List?> _read() async {
    try {
      return await widget.client.coverArt(widget.coverArt!);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return ClipRect(
      child: ColoredBox(
        color: scheme.surface,
        child: Stack(
          children: [
            if (GlassScope.effectsEnabled(context))
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: FutureBuilder<Uint8List?>(
                      future: _artwork,
                      builder: (context, snapshot) => Stack(
                        fit: StackFit.expand,
                        children: [
                          if (snapshot.data != null)
                            ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: 48,
                                sigmaY: 48,
                              ),
                              child: Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  scheme.surface.withValues(
                                    alpha: dark
                                        ? (widget.immersive ? .30 : .96)
                                        : (widget.immersive ? .82 : .97),
                                  ),
                                  scheme.surface.withValues(
                                    alpha: dark
                                        ? (widget.immersive ? .52 : .65)
                                        : .90,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (snapshot.data == null)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(.8, -.7),
                                  radius: 1.4,
                                  colors: [
                                    scheme.primary.withValues(alpha: .1),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Material(type: MaterialType.transparency, child: widget.child),
          ],
        ),
      ),
    );
  }
}
