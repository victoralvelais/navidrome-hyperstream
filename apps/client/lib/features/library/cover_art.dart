import 'package:hyperstream_client/widgets/app_icon.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';
import '../../services/source_artwork.dart';

class CoverArt extends StatefulWidget {
  const CoverArt({
    super.key,
    required this.client,
    required this.id,
    this.radius = 16,
    this.externalUri,
  });
  final NavidromeClient client;
  final String? id;
  final double radius;
  final Uri? externalUri;

  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.id != widget.id ||
        oldWidget.externalUri != widget.externalUri) {
      _load();
    }
  }

  void _load() {
    _bytes = widget.externalUri != null
        ? SourceArtwork.load(widget.externalUri!)
        : widget.id == null
        ? null
        : widget.client.coverArt(widget.id!);
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: LayoutBuilder(
      builder: (context, constraints) => Center(
        child: AppIcon(Icons.album_outlined, size: constraints.maxWidth * .3),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    child: AspectRatio(
      aspectRatio: 1,
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    ),
  );
}
