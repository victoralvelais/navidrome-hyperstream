import 'package:flutter/material.dart';

import '../services/library_catalog.dart';

/// Displays the catalog total, never page offsets or a running fetched count.
class LibrarySyncStatus extends StatelessWidget {
  const LibrarySyncStatus({super.key, required this.catalog});
  final LibraryCatalog catalog;

  @override
  Widget build(BuildContext context) {
    if (!catalog.loading) return const SizedBox.shrink();
    final total = catalog.syncTotal;
    final text = total == null
        ? 'Syncing library'
        : '${MaterialLocalizations.of(context).formatDecimal(total)} ${total == 1 ? 'track' : 'tracks'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: catalog.syncProgress,
            semanticsLabel: 'Syncing library${total == null ? '' : ', $text'}',
          ),
          const SizedBox(height: 8),
          Text(text),
        ],
      ),
    );
  }
}
