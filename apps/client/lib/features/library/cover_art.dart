import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';

class CoverArt extends StatefulWidget {
  const CoverArt({super.key, required this.client, required this.id});
  final NavidromeClient client;
  final String? id;

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
    if (oldWidget.client != widget.client || oldWidget.id != widget.id) _load();
  }

  void _load() {
    _bytes = widget.id == null ? null : widget.client.coverArt(widget.id!);
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: LayoutBuilder(
      builder: (context, constraints) => Center(
        child: Icon(Icons.album_outlined, size: constraints.maxWidth * .3),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
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
