import 'package:flutter/material.dart';

import '../../services/mornye_sources.dart';
import '../../services/music_provider.dart';
import '../../widgets/glass_surface.dart';
import '../sources/source_verification_flow.dart';

class MornyeSourceSettings extends StatefulWidget {
  const MornyeSourceSettings({super.key, required this.sources});
  final MornyeSources sources;
  @override
  State<MornyeSourceSettings> createState() => _MornyeSourceSettingsState();
}

class _MornyeSourceSettingsState extends State<MornyeSourceSettings> {
  String? busy, message;
  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      busy = id;
      message = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => message = error is SourceException
              ? error.message
              : 'This action could not finish. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> _settings(MornyeExtension extension) async {
    final value = await widget.sources.execute({
      'op': 'settings',
      'id': extension.id,
    }) as Map;
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ProviderSettings(
          sources: widget.sources,
          extension: extension,
          fields: List<Map<String, dynamic>>.from(
            (value['fields'] as List? ?? []).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          ),
          values: Map<String, dynamic>.from(value['values'] as Map),
        ),
      ),
    );
  }

  void _verified(MornyeExtension extension) {
    if (mounted) {
      setState(
        () => message =
            '${extension.name} verification completed. Try your search or playback again.',
      );
    }
  }

  Future<void> _pasteVerification(MornyeExtension extension) async {
    final complete = await showDialog<bool>(
      context: context,
      builder: (_) => SourceVerificationDialog(
        sources: widget.sources,
        providerId: extension.id,
      ),
    );
    if (complete == true) _verified(extension);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.sources, widget.sources.verification]),
    builder: (context, _) {
      final sources = widget.sources;
      final disabled = busy != null || sources.busy != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Music extensions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Search songs or paste a public playlist link. Play here, then send the songs you want to your remote folder as MP3 320.',
          ),
          const SizedBox(height: 16),
          for (final extension in sources.extensions) ...[
            GlassSurface(
              radius: 24,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(extension.name),
                      subtitle: Text(
                        '${extension.audio ? 'Catalog, playback and downloads' : 'Catalog · uses your chosen audio source'}\n${extension.version}',
                      ),
                      trailing: extension.installed
                          ? Switch.adaptive(
                              value: extension.enabled,
                              onChanged: disabled
                                  ? null
                                  : (v) => _run(
                                      extension.id,
                                      () => sources.setEnabled(extension.id, v),
                                    ),
                            )
                          : OutlinedButton(
                              onPressed: disabled
                                  ? null
                                  : () => _run(
                                      extension.id,
                                      () => sources.install(extension),
                                    ),
                              child: Text(
                                sources.busy == extension.id
                                    ? 'Installing…'
                                    : 'Install',
                              ),
                            ),
                    ),
                    if (extension.installed && extension.enabled)
                      Wrap(
                        spacing: 12,
                        children: [
                          if (extension.requiresVerification)
                            TextButton.icon(
                              onPressed: disabled
                                  ? null
                                  : () => _run(extension.id, () async {
                                      final complete = await sources
                                          .requestVerification(
                                            extension.id,
                                            fallback: (id) =>
                                                showSourceVerification(
                                                  context,
                                                  sources,
                                                  id,
                                                ),
                                          );
                                      if (!mounted) return;
                                      if (complete) {
                                        _verified(extension);
                                      }
                                    }),
                              icon: Icon(
                                sources.verification.value == extension.id
                                    ? Icons.warning_amber_rounded
                                    : Icons.verified_user_outlined,
                              ),
                              label: Text(
                                busy == extension.id ? 'Working…' : 'Verify',
                              ),
                            ),
                          if (extension.requiresVerification)
                            TextButton.icon(
                              onPressed: disabled
                                  ? null
                                  : () => _run(
                                      extension.id,
                                      () => _pasteVerification(extension),
                                    ),
                              icon: const Icon(Icons.content_paste_rounded),
                              label: const Text('Paste verification'),
                            ),
                          TextButton.icon(
                            onPressed: disabled
                                ? null
                                : () => _run(
                                    extension.id,
                                    () => _settings(extension),
                                  ),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Configure'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (sources.enabled.any((e) => e.audio))
            DropdownButtonFormField<String>(
              key: ValueKey(sources.audioProvider),
              initialValue: sources.audioProvider,
              decoration: const InputDecoration(
                labelText: 'Audio source for Spotify',
              ),
              items: [
                for (final e in sources.enabled.where((e) => e.audio))
                  DropdownMenuItem(value: e.id, child: Text(e.name)),
              ],
              onChanged: disabled
                  ? null
                  : (id) {
                      if (id != null) {
                        _run('audio', () => sources.choose(audio: id));
                      }
                    },
            ),
          if (message ?? sources.error case final String error)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error),
            ),
          if (sources.extensions.isEmpty)
            TextButton(
              onPressed: disabled
                  ? null
                  : () => _run('restore', sources.restore),
              child: const Text('Try opening music sources again'),
            ),
        ],
      );
    },
  );
}

class _ProviderSettings extends StatefulWidget {
  const _ProviderSettings({
    required this.sources,
    required this.extension,
    required this.fields,
    required this.values,
  });
  final MornyeSources sources;
  final MornyeExtension extension;
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> values;
  @override
  State<_ProviderSettings> createState() => _ProviderSettingsState();
}

class _ProviderSettingsState extends State<_ProviderSettings> {
  late final values = <String, dynamic>{
    for (final field in widget.fields)
      field['key'] as String: widget.values[field['key']] ?? field['default'],
  };
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.extension.name)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Provider settings are stored securely on this device.'),
        const SizedBox(height: 20),
        for (final field in widget.fields)
          if (field['type'] == 'boolean')
            SwitchListTile.adaptive(
              title: Text(field['label'] as String? ?? field['key'] as String),
              value: values[field['key']] == true,
              onChanged: saving
                  ? null
                  : (v) => setState(() => values[field['key'] as String] = v),
            )
          else if (field['type'] != 'button')
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: TextFormField(
                initialValue: values[field['key']]?.toString() ?? '',
                enabled: !saving,
                obscureText: field['secret'] == true,
                autocorrect: false,
                enableSuggestions: field['secret'] != true,
                decoration: InputDecoration(
                  labelText:
                      field['label'] as String? ?? field['key'] as String,
                  helperText: field['description'] as String?,
                  helperMaxLines: 4,
                ),
                onChanged: (v) => values[field['key'] as String] =
                    field['type'] == 'number' ? num.tryParse(v) : v,
              ),
            ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await widget.sources.execute({
                      'op': 'save_settings',
                      'id': widget.extension.id,
                      'values': values,
                    });
                    if (context.mounted) Navigator.pop(context);
                  } on Object {
                    if (mounted) {
                      setState(() {
                        saving = false;
                        error = 'Could not save these settings. Try again.';
                      });
                    }
                  }
                },
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
