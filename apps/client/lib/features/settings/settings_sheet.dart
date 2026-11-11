import 'package:flutter/material.dart';

import '../../services/playback_service.dart';
import '../player/volume_controls.dart';

Future<void> showSettings(
  BuildContext context,
  PlaybackService playback, {
  VoidCallback? onDisconnect,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (context) =>
      SettingsSheet(playback: playback, onDisconnect: onDisconnect),
);

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.playback, this.onDisconnect});
  final PlaybackService playback;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          playback.preferences,
          playback.settingsError,
        ]),
        builder: (context, _) {
          final preferences = playback.preferences;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Settings',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close settings',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemeMode>(
                isExpanded: true,
                initialValue: preferences.themeMode,
                decoration: const InputDecoration(labelText: 'Theme'),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('Follow system'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value != null) preferences.setThemeMode(value);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Glass effects'),
                subtitle: const Text(
                  'Soft blur and translucent controls. Turn off for solid surfaces.',
                ),
                value: preferences.glassEffects,
                onChanged: preferences.setGlassEffects,
              ),
              const SizedBox(height: 28),
              Text(
                'Music volume',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              VolumeControls(playback: playback),
              const Text(
                'Adjusts Hyperstream only. Your device volume still sets the overall level.',
              ),
              const SizedBox(height: 20),
              if (playback.supportsMixing)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mix with other audio'),
                  subtitle: const Text(
                    'Allow music alongside other apps. Calls may still pause playback.',
                  ),
                  value: preferences.mixWithOthers,
                  onChanged: playback.setMixWithOthers,
                )
              else
                const Text(
                  'Windows mixes apps automatically. Calls can lower music according to your Windows sound settings.',
                ),
              if (playback.settingsError.value ?? preferences.notice
                  case final String message) ...[
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (onDisconnect != null) ...[
                const SizedBox(height: 28),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disconnect from server'),
                  subtitle: const Text(
                    'Stop playback and remove the saved account from this device.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    onDisconnect!();
                  },
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
