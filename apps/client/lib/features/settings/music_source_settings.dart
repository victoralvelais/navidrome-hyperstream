import 'package:flutter/material.dart';

import '../../services/music_sources.dart';
import '../../services/source_imports.dart';
import '../../widgets/glass_surface.dart';
import '../search/source_import_action.dart';

class MusicSourceSettings extends StatefulWidget {
  const MusicSourceSettings({super.key, this.sources});
  final MusicSources? sources;
  @override
  State<MusicSourceSettings> createState() => _MusicSourceSettingsState();
}

class _MusicSourceSettingsState extends State<MusicSourceSettings> {
  late final MusicSources sources = widget.sources ?? MusicSources.instance;
  late final TextEditingController endpoint = TextEditingController(
    text: sources.endpoint,
  );
  late bool enabled = sources.enabled;
  String? message;

  Future<void> _save() async {
    try {
      await sources.save(endpoint: endpoint.text, enabled: enabled);
      if (mounted) {
        setState(
          () => message = 'Music source saved. Open Search > Online to browse.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => message = error is FormatException
              ? error.message
              : sources.error,
        );
      }
    }
  }

  @override
  void dispose() {
    endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sources, SourceImports.instance]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSurface(
          radius: 24,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Monochrome'),
                  subtitle: const Text(
                    'Search and stream outside your library',
                  ),
                  value: enabled,
                  onChanged: sources.busy
                      ? null
                      : (value) => setState(() => enabled = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: endpoint,
                  enabled: !sources.busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Monochrome tracks API',
                    hintText: MusicSources.defaultEndpoint,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Downloads convert to MP3 320 and go to the destination in Remote folder.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: sources.busy ? null : _save,
                  child: Text(sources.busy ? 'Saving…' : 'Save source'),
                ),
                if (message ?? sources.error case final String text) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(text)),
                ],
              ],
            ),
          ),
        ),
        if (SourceImports.instance.issue case final issue?) ...[
          const SizedBox(height: 20),
          Text(issue.message),
          if (!issue.uncertain)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: SourceImports.instance.active
                    ? null
                    : () => retrySourceImport(context),
                child: Text(
                  issue.retryWithActivity
                      ? 'Retry with iOS activity'
                      : 'Retry remaining songs',
                ),
              ),
            ),
        ],
      ],
    ),
  );
}
