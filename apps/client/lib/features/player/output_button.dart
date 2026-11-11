import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/pull_to_refresh.dart';

/// iOS owns its route sheet; Windows changes only this app's MediaPlayer output.
class OutputButton extends StatelessWidget {
  const OutputButton({super.key});
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return SizedBox(
        width: 44,
        height: 44,
        child: UiKitView(
          key: ValueKey(dark),
          viewType: 'dev.hyperstream/audio_route_picker',
          creationParams: {'dark': dark},
          creationParamsCodec: const StandardMessageCodec(),
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return IconButton(
        tooltip: 'Choose audio output',
        icon: const Icon(Icons.speaker_group_outlined),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          constraints: const BoxConstraints(maxWidth: 560),
          builder: (_) => const AudioOutputsSheet(),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class AudioOutputsSheet extends StatefulWidget {
  const AudioOutputsSheet({super.key});
  @override
  State<AudioOutputsSheet> createState() => _AudioOutputsSheetState();
}

class _AudioOutputsSheetState extends State<AudioOutputsSheet> {
  static const _channel = MethodChannel('dev.hyperstream/audio_outputs');
  List<Map<Object?, Object?>> _outputs = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outputs = await _channel.invokeListMethod<Object?>('getOutputs');
      if (mounted) {
        setState(
          () => _outputs = (outputs ?? []).cast<Map<Object?, Object?>>(),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read audio outputs. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod<void>('setOutput', id);
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not use that output. It may have disconnected.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .6,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Audio output',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Close audio outputs',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: PullToRefresh(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final output in _outputs)
                  ListTile(
                    leading: const Icon(Icons.speaker_outlined),
                    title: Text(output['name'] as String),
                    selected: output['selected'] == true,
                    trailing: output['selected'] == true
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: _busy ? null : () => _select(output['id'] as String),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
