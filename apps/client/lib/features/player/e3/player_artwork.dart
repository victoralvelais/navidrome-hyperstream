import 'package:flutter/material.dart';

import '../../../services/navidrome_client.dart';
import '../../../services/source_artwork.dart';
import 'album_palette.dart';

/// Loads artwork through the same authenticated, bounded caches as the library.
/// Only memory images reach the presentation layer, never credentialed URLs.
class PlayerArtwork extends StatefulWidget {
  const PlayerArtwork({
    super.key,
    required this.client,
    this.coverArt,
    this.externalUri,
    required this.builder,
  });
  final NavidromeClient client;
  final String? coverArt;
  final Uri? externalUri;
  final Widget Function(BuildContext, ImageProvider?, AlbumPalette) builder;

  @override
  State<PlayerArtwork> createState() => _PlayerArtworkState();
}

class _PlayerArtworkState extends State<PlayerArtwork> {
  ImageProvider? _image;
  AlbumPalette _palette = AlbumPalette.fallback;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PlayerArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.coverArt != widget.coverArt ||
        oldWidget.externalUri != widget.externalUri) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    // Never display an old album under a new song's title while it loads.
    _image = null;
    if (widget.coverArt == null && widget.externalUri == null) {
      _palette = AlbumPalette.fallback;
      return;
    }
    try {
      final bytes = await (widget.externalUri != null
          ? SourceArtwork.load(widget.externalUri!)
          : widget.client.coverArt(widget.coverArt!));
      if (!mounted || generation != _generation) return;
      final image = MemoryImage(bytes);
      setState(() => _image = image);
      final palette = await AlbumPalette.fromImage(image);
      if (mounted && generation == _generation) {
        setState(() => _palette = palette);
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _palette = AlbumPalette.fallback);
      }
    }
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<AlbumPalette>(
    tween: AlbumPaletteTween(end: _palette),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 800),
    curve: Curves.easeOut,
    builder: (context, palette, _) => widget.builder(context, _image, palette),
  );
}
