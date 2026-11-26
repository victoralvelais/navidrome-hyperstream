import 'package:hyperstream_client/widgets/app_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/navidrome_client.dart';
import '../../services/remote_transfer.dart';
import '../../services/source_imports.dart';
import '../../services/source_import_status.dart';
import '../../widgets/glass_overlays.dart';

class SourceDownloadButton extends StatefulWidget {
  const SourceDownloadButton({
    super.key,
    required this.client,
    required this.tracks,
    this.imports,
  });
  final NavidromeClient client;
  final List<Track> tracks;
  final SourceImports? imports;
  @override
  State<SourceDownloadButton> createState() => _SourceDownloadButtonState();
}

class _SourceDownloadButtonState extends State<SourceDownloadButton> {
  SourceImports get imports => widget.imports ?? SourceImports.instance;
  Timer? _confirmation;
  DateTime? _confirmedAt;
  @override
  void initState() {
    super.initState();
    unawaited(imports.restore());
  }

  @override
  void dispose() {
    _confirmation?.cancel();
    super.dispose();
  }

  Future<void> _sendAgain({required bool includeSaved}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('Send again?'),
        content: const Text(
          'A previous save completed or could not be confirmed. Check the remote folder first to avoid a duplicate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send again'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _send(includeSaved: includeSaved);
  }

  void _send({bool includeSaved = false}) {
    final tracks = widget.tracks
        .where(
          (track) =>
              includeSaved ||
              imports.statusFor(track)?.phase != SourceImportPhase.saved,
        )
        .toList();
    final retry =
        imports.issue != null &&
        !imports.issue!.uncertain &&
        imports.remaining.isNotEmpty &&
        imports.remaining.length == tracks.length &&
        imports.remaining.every(
          (track) => tracks.any(
            (item) => item.source?.identity == track.source?.identity,
          ),
        );
    unawaited(
      _report(
        ScaffoldMessenger.of(context),
        retry ? imports.retry() : imports.send(widget.client, tracks),
        imports: imports,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([imports, imports.remote]),
    builder: (context, _) {
      final statuses = widget.tracks.map(imports.statusFor).toList();
      final allSaved =
          statuses.isNotEmpty &&
          statuses.every((s) => s?.phase == SourceImportPhase.saved);
      final status = allSaved
          ? statuses.reduce((a, b) => a!.savedAt!.isAfter(b!.savedAt!) ? a : b)
          : statuses.where((s) => s?.busy == true).firstOrNull ??
                statuses
                    .where((s) => s?.phase == SourceImportPhase.uncertain)
                    .firstOrNull ??
                statuses
                    .where((s) => s?.phase == SourceImportPhase.failed)
                    .firstOrNull;
      final busy = status?.busy == true;
      final recent =
          allSaved &&
          _confirmedAt != status!.savedAt &&
          DateTime.now().difference(status.savedAt!) <
              const Duration(seconds: 2);
      _confirmation?.cancel();
      if (recent) {
        _confirmation = Timer(
          const Duration(seconds: 2) -
              DateTime.now().difference(status.savedAt!),
          () {
            if (mounted) setState(() => _confirmedAt = status.savedAt);
          },
        );
      }
      final failed =
          status?.phase == SourceImportPhase.failed ||
          status?.phase == SourceImportPhase.uncertain;
      final label =
          status?.label ??
          (widget.tracks.length == 1
              ? 'Download song to remote folder'
              : 'Download album to remote folder');
      final color = allSaved
          ? Theme.of(context).colorScheme.primary
          : failed
          ? Theme.of(context).colorScheme.error
          : null;
      final icon = busy
          ? SizedBox.square(
              dimension: 23,
              child: CircularProgressIndicator(
                value: status?.progress,
                strokeWidth: 2.5,
                semanticsLabel: label,
                semanticsValue: status?.progress == null
                    ? null
                    : '${(status!.progress! * 100).round()}%',
              ),
            )
          : AppIcon(
              recent
                  ? Icons.check_rounded
                  : allSaved
                  ? Icons.inventory_2_outlined
                  : failed
                  ? Icons.warning_amber_rounded
                  : Icons.download_rounded,
              color: color,
            );
      return IconButton(
        tooltip: recent ? 'Saved to remote folder' : label,
        icon: icon,
        onPressed:
            busy ||
                imports.active ||
                widget.tracks.isEmpty ||
                widget.tracks.any((track) => track.source?.available != true)
            ? null
            : allSaved || status?.phase == SourceImportPhase.uncertain
            ? () => _sendAgain(includeSaved: allSaved)
            : _send,
      );
    },
  );
}

void sendSourceTracks(
  BuildContext context,
  NavidromeClient client,
  List<Track> tracks,
) {
  final messenger = ScaffoldMessenger.of(context);
  unawaited(_report(messenger, SourceImports.instance.send(client, tracks)));
}

void retrySourceImport(BuildContext context) {
  unawaited(
    _report(ScaffoldMessenger.of(context), SourceImports.instance.retry()),
  );
}

Future<void> _report(
  ScaffoldMessengerState messenger,
  Future<RemoteTransferResult> operation, {
  SourceImports? imports,
}) async {
  imports ??= SourceImports.instance;
  final result = await operation;
  if (!messenger.mounted || (result.success && result.notified)) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(result.message),
      duration: result.success
          ? const Duration(seconds: 4)
          : const Duration(days: 1),
      showCloseIcon: true,
      action:
          !result.success &&
              !result.uncertain &&
              !imports.active &&
              identical(result, imports.issue) &&
              imports.remaining.isNotEmpty
          ? SnackBarAction(
              label: 'Retry',
              onPressed: () {
                if (identical(result, imports!.issue)) {
                  unawaited(
                    _report(messenger, imports.retry(), imports: imports),
                  );
                }
              },
            )
          : null,
    ),
  );
}
