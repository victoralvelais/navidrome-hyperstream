import 'package:hyperstream_client/widgets/app_icon.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';
import '../../services/source_artwork.dart';
import '../../models/source_reference.dart';
import '../../widgets/music_source_icon.dart';

class CoverArt extends StatefulWidget {
  const CoverArt({
    super.key,
    required this.client,
    required this.id,
    this.radius = 16,
    this.externalUri,
    this.sourceId,
  });
  final NavidromeClient client;
  final String? id;
  final double radius;
  final Uri? externalUri;
  final String? sourceId;

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) => snapshot.hasData
                ? Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(context),
                  )
                : _placeholder(context),
          ),
          if (widget.sourceId case final sourceId?)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: MusicSourceIcon(
                  sourceId: sourceId,
                  name: musicSourceName(sourceId),
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
