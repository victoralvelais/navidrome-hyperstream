import '../../widgets/hyperstream_mark.dart';
import '../../widgets/glass_overlays.dart';
import '../../widgets/glass_surface.dart';

import 'package:flutter/material.dart';

import '../../services/account_session.dart';
import '../../services/playback_service.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/floating_chrome.dart';
import '../connect/connection_screen.dart';
import '../player/volume_controls.dart';

/// Part of the Home navigation stack, so the floating player stays available.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.playback,
    this.session,
    this.onDisconnect,
    this.onPageChanged,
  });
  final PlaybackService playback;
  final AccountSession? session;
  final VoidCallback? onDisconnect;
  final ValueChanged<bool>? onPageChanged;
  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  String? _page;
  bool _confirmingDisconnect = false;
  String get pageTitle => _page ?? 'Home';
  bool back() {
    if (_page == null) return false;
    setState(() => _page = null);
    widget.onPageChanged?.call(false);
    return true;
  }

  void _open(String page) {
    setState(() => _page = page);
    widget.onPageChanged?.call(true);
  }

  Future<void> _confirmDisconnect() async {
    final session = widget.session;
    if (_confirmingDisconnect ||
        session?.busy == true ||
        widget.onDisconnect == null) {
      return;
    }
    final serverId = session?.activeServerId;
    final name =
        session?.savedServers
            .where((server) => server.id == serverId)
            .firstOrNull
            ?.displayName ??
        'this server';
    setState(() => _confirmingDisconnect = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => GlassAlertDialog(
          title: const Text('Disconnect from server?'),
          content: Text(
            'Stop playback and remove the saved connection to $name from this device?',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          widget.session != session ||
          session?.busy == true ||
          session?.activeServerId != serverId) {
        return;
      }
      widget.onDisconnect?.call();
    } finally {
      if (mounted) setState(() => _confirmingDisconnect = false);
    }
  }

  Future<void> _remove(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'Remove this saved connection from this device. Your server and music will stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session!.removeServer(id);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not remove this saved server. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Widget _row(
    String title,
    String subtitle, {
    VoidCallback? onTap,
    Widget? trailing,
  }) => ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  );

  Widget _group(List<Widget> rows) => GlassSurface(
    radius: 24,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1),
            ),
          rows[i],
        ],
      ],
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.playback.preferences,
      widget.playback.settingsError,
      widget.playback.listeningNotice,
      if (widget.session != null) widget.session!,
    ]),
    builder: (context, _) {
      final preferences = widget.playback.preferences;
      final session = widget.session;
      return ListView(
        key: ValueKey(_page),
        padding: EdgeInsets.fromLTRB(
          20,
          PageChrome.insetOf(context) + 8,
          20,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          Row(
            children: [
              if (_page != null && !PageChrome.present(context))
                IconButton(
                  tooltip: 'Back to home',
                  onPressed: back,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
              if (_page == null) ...[
                const HyperstreamMark(size: 60),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _page == null
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Hyperstream',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                        )
                      : Text(
                          _page!,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_page == null) ...[
            _group([
              _row(
                'Appearance',
                'Theme and glass effects',
                onTap: () => _open('Appearance'),
              ),
            ]),
            _label('Listening'),
            _group([
              _row(
                'Playback',
                'Music volume and other audio',
                onTap: () => _open('Playback'),
              ),
              if (session != null || widget.onDisconnect != null)
                _row(
                  'Servers',
                  session == null
                      ? 'Connection settings'
                      : '${session.savedServers.length} saved connections',
                  onTap: () => _open('Servers'),
                ),
            ]),
          ],
          if (_page == 'Appearance')
            _group([
              Padding(
                padding: const EdgeInsets.all(20),
                child: GlassDropdownField<ThemeMode>(
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
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) preferences.setThemeMode(value);
                  },
                ),
              ),
              SwitchListTile.adaptive(
                title: const Text('Glass effects'),
                subtitle: const Text('Soft blur and translucent controls'),
                value: preferences.glassEffects,
                onChanged: preferences.setGlassEffects,
              ),
            ]),
          if (_page == 'Playback') ...[
            _group([
              SwitchListTile.adaptive(
                title: const Text('Report listening history'),
                subtitle: const Text(
                  'Count qualified listens in Navidrome for Recent Radio and play history. Your server may also send them to its connected scrobbling services.',
                ),
                value: preferences.reportListens,
                onChanged: preferences.setReportListens,
              ),
            ]),
            if (widget.playback.listeningNotice.value case final String notice)
              Padding(padding: const EdgeInsets.all(16), child: Text(notice)),
            const SizedBox(height: 20),
            _group([
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Music volume',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    VolumeControls(playback: widget.playback),
                    const Text(
                      'Adjusts Hyperstream only. Your device volume still sets the overall level.',
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            if (widget.playback.supportsMixing)
              _group([
                SwitchListTile.adaptive(
                  title: const Text('Mix with other audio'),
                  subtitle: const Text(
                    'Allow music alongside other apps. Calls may still pause playback.',
                  ),
                  value: preferences.mixWithOthers,
                  onChanged: widget.playback.setMixWithOthers,
                ),
              ])
            else
              const Text(
                'Windows mixes apps automatically. Calls can lower music according to your Windows sound settings.',
              ),
          ],
          if (_page == 'Servers' && session != null) ...[
            _group([
              for (final server in session.savedServers)
                _row(
                  server.displayName,
                  '${server.username} · ${server.serverUrl}',
                  onTap: session.busy
                      ? null
                      : () => session.switchServer(
                          server.id,
                          beforeSwitch: widget.playback.reset,
                        ),
                  trailing: server.id == session.activeServerId
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : IconButton(
                          tooltip: 'Remove ${server.displayName}',
                          onPressed: session.busy
                              ? null
                              : () => _remove(server.id, server.displayName),
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Add connection'),
                onTap: session.busy ? null : () => _open('Add connection'),
              ),
            ]),
            const SizedBox(height: 12),
            const Text(
              'Switching servers stops the current queue. Each library stays separate.',
            ),
            if (session.busy) const LinearProgressIndicator(),
            if (session.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  session.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
          if (_page == 'Servers' &&
              (session != null || widget.onDisconnect != null)) ...[
            _label('Account'),
            _group([
              if (session != null)
                _row(
                  'Connected to',
                  '${session.username ?? ''}\n${session.serverUrl ?? ''}',
                  trailing: const Icon(Icons.check_circle_outline_rounded),
                ),
              if (widget.onDisconnect != null)
                _row(
                  'Disconnect from server',
                  'Stop playback and forget this connection',
                  onTap: session?.busy == true || _confirmingDisconnect
                      ? null
                      : _confirmDisconnect,
                ),
            ]),
          ],
          if (_page == 'Add connection' && session != null)
            ServerSignInForm(
              session: session,
              adding: true,
              beforeSwitch: widget.playback.reset,
            ),
          if (widget.playback.settingsError.value ?? preferences.notice
              case final String message)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const DockSpacer(),
        ],
      );
    },
  );
}
