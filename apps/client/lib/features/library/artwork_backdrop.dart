import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';
import '../../widgets/glass_surface.dart';

/// Samples actual cover pixels; no artwork URLs or credentials enter widgets.
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

class _ArtworkData {
  const _ArtworkData(this.bytes, this.color);
  final Uint8List bytes;
  final Color? color;
}

class _ArtworkIdentity extends InheritedWidget {
  const _ArtworkIdentity({
    required this.client,
    required this.coverArt,
    required super.child,
  });
  final NavidromeClient client;
  final String? coverArt;
  @override
  bool updateShouldNotify(_ArtworkIdentity oldWidget) =>
      oldWidget.client != client || oldWidget.coverArt != coverArt;
}

class _ArtworkBackdropState extends State<ArtworkBackdrop> {
  static final _cache = Expando<Map<String, Future<_ArtworkData?>>>();
  Future<_ArtworkData?>? _artwork;
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
    final id = widget.coverArt;
    if (id == null) {
      _artwork = null;
      return;
    }
    // Bounded, account-scoped memory cache shared by nested detail/player views.
    final cache = _cache[widget.client] ??= {};
    final existing = cache.remove(id);
    final future = existing ?? _read(widget.client, id);
    cache[id] = future;
    while (cache.length > 12) {
      cache.remove(cache.keys.first);
    }
    _artwork = future;
  }

  static Future<_ArtworkData?> _read(NavidromeClient client, String id) async {
    try {
      final bytes = await client.coverArt(id);
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final pixels = await frame.image.toByteData();
          return _ArtworkData(
            bytes,
            pixels == null
                ? null
                : artworkAccent(
                    pixels.buffer.asUint8List(
                      pixels.offsetInBytes,
                      pixels.lengthInBytes,
                    ),
                  ),
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } on Object {
      _cache[client]?.remove(id);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = context
        .dependOnInheritedWidgetOfExactType<_ArtworkIdentity>();
    if (parent?.client == widget.client &&
        parent?.coverArt == widget.coverArt) {
      return widget.child;
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final effects = GlassScope.effectsEnabled(context);
    return FutureBuilder<_ArtworkData?>(
      future: _artwork,
      builder: (context, snapshot) {
        final art = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        final tone = effects ? art?.color : null;
        final base = tone == null
            ? scheme.surface
            : Color.lerp(scheme.surface, tone, dark ? .38 : .18)!;
        return _ArtworkIdentity(
          client: widget.client,
          coverArt: widget.coverArt,
          child: ArtworkTint(
            color: tone,
            child: ClipRect(
              child: ColoredBox(
                color: base,
                child: Stack(
                  children: [
                    if (effects)
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (art != null)
                                  ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(
                                      sigmaX: 64,
                                      sigmaY: 64,
                                    ),
                                    child: Image.memory(
                                      art.bytes,
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
                                        base.withValues(
                                          alpha: dark
                                              ? (widget.immersive ? .60 : .82)
                                              : .90,
                                        ),
                                        base.withValues(
                                          alpha: dark ? .90 : .97,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (art == null)
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
                    Material(
                      type: MaterialType.transparency,
                      child: widget.child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Favor repeated chromatic pixels over black borders and white lettering.
@visibleForTesting
Color? artworkAccent(Uint8List rgba) {
  final buckets = <int, List<double>>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (rgba[i + 3] < 128) continue;
    final high = [r, g, b].reduce((a, b) => a > b ? a : b);
    final low = [r, g, b].reduce((a, b) => a < b ? a : b);
    if (high < 25 || low > 235) continue;
    final weight = .15 + (high - low) / 255;
    final key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5);
    final bucket = buckets.putIfAbsent(key, () => [0, 0, 0, 0]);
    bucket[0] += weight;
    bucket[1] += r * weight;
    bucket[2] += g * weight;
    bucket[3] += b * weight;
  }
  if (buckets.isEmpty) return null;
  final best = buckets.values.reduce((a, b) => a[0] >= b[0] ? a : b);
  return Color.fromARGB(
    255,
    (best[1] / best[0]).round(),
    (best[2] / best[0]).round(),
    (best[3] / best[0]).round(),
  );
}
