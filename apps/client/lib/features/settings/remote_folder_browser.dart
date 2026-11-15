import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/remote_folder.dart';

/// Embedded in the settings scroll view, with a bounded list for large shares.
class RemoteFolderBrowser extends StatefulWidget {
  const RemoteFolderBrowser({
    super.key,
    required this.remote,
    required this.connection,
    required this.onVerified,
  });

  final RemoteFolders remote;
  final RemoteConnection connection;
  final VoidCallback onVerified;

  @override
  State<RemoteFolderBrowser> createState() => _RemoteFolderBrowserState();
}

class _RemoteFolderBrowserState extends State<RemoteFolderBrowser> {
  final _form = GlobalKey<FormState>();
  final _share = TextEditingController();
  final _folder = TextEditingController();
  RemoteDestination? _location;
  List<String> _names = [];
  bool _loading = false;
  bool _saving = false;
  bool _manual = false;
  bool _ready = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _share.text = widget.remote.destination?.share ?? '';
    _folder.text = widget.remote.destination?.folder ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(null));
    });
  }

  Future<void> _load(RemoteDestination? location) async {
    if (_loading || _saving) return;
    setState(() {
      _location = location;
      _names = [];
      _loading = true;
      _ready = false;
      _saved = false;
      _error = null;
      _manual = false;
    });
    try {
      final names = location == null
          ? await widget.remote.browseShares(widget.connection)
          : await widget.remote.browseFolders(location);
      if (!mounted) return;
      setState(() {
        _names = names;
        _ready = true;
      });
      widget.onVerified();
    } on Object catch (e) {
      if (mounted) setState(() => _error = remoteFolderError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(String name) {
    final current = _location;
    final next = current == null
        ? widget.connection.destination(share: name)
        : widget.connection.destination(
            share: current.share,
            folder: current.path(name),
          );
    unawaited(_load(next));
  }

  void _up() {
    final current = _location!;
    final parent = current.folder.split('/')..removeLast();
    unawaited(
      _load(
        current.folder.isEmpty
            ? null
            : widget.connection.destination(
                share: current.share,
                folder: parent.join('/'),
              ),
      ),
    );
  }

  Future<void> _save() async {
    if (_loading || _saving || widget.remote.busy) return;
    if (_manual && !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      final location = _manual
          ? widget.connection.destination(
              share: _share.text,
              folder: _folder.text,
            )
          : _location!;
      await widget.remote.testAndSave(location);
      if (!mounted) return;
      setState(() => _saved = true);
      widget.onVerified();
    } on Object catch (e) {
      if (!mounted) return;
      final stage = e is RemoteCheckException
          ? switch (e.stage) {
              RemoteCheckStage.share => 'Share check failed. ',
              RemoteCheckStage.folder => 'Folder check failed. ',
              RemoteCheckStage.write => 'Write check failed. ',
              RemoteCheckStage.save => 'Folder verified. ',
              _ => '',
            }
          : '';
      setState(() => _error = '$stage${remoteFolderError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editManually() {
    if (_loading || _saving || widget.remote.busy) return;
    if (_location != null) {
      _share.text = _location!.share;
      _folder.text = _location!.folder;
    }
    setState(() {
      _manual = true;
      _saved = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _share.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_loading && !_saving && !widget.remote.busy;
    final selected = widget.remote.destination;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected != null) ...[
          Text('Saved folder', style: Theme.of(context).textTheme.labelLarge),
          Text(selected.address),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: enabled ? () => _load(selected) : null,
              child: const Text('Open saved folder'),
            ),
          ),
          const Divider(),
        ],
        if (_manual)
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _share,
                  enabled: enabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {
                    _saved = false;
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Share name',
                    hintText: 'Music',
                  ),
                  validator: (value) => value?.trim().isEmpty != false
                      ? 'Enter the share name.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _folder,
                  enabled: enabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {
                    _saved = false;
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Subfolder (optional)',
                    helperText: 'Leave empty to use the share itself.',
                    helperMaxLines: 3,
                  ),
                  onFieldSubmitted: enabled ? (_) => _save() : null,
                ),
              ],
            ),
          )
        else ...[
          if (_location == null)
            Text(
              'Shared folders',
              style: Theme.of(context).textTheme.titleMedium,
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled ? _up : null,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(
                  _location!.folder.isEmpty ? 'All shares' : 'Up one folder',
                ),
              ),
            ),
            Text(
              [
                _location!.share,
                if (_location!.folder.isNotEmpty) _location!.folder,
              ].join(' / '),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 12),
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              _location == null
                  ? 'Finding shared folders…'
                  : 'Loading folders…',
            ),
          ] else if (_ready && _names.isEmpty)
            Text(
              _location == null
                  ? 'No shared folders were listed. You can enter a share name manually.'
                  : 'This folder has no subfolders.',
            )
          else if (_names.isNotEmpty)
            SizedBox(
              height: min(320, _names.length * 72.0),
              child: ListView.builder(
                primary: false,
                itemCount: _names.length,
                itemBuilder: (context, index) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    _names[index],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: enabled ? () => _open(_names[index]) : null,
                ),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          if (!_manual && !_ready)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: enabled ? () => _load(_location) : null,
                child: const Text('Try again'),
              ),
            ),
        ],
        if (_manual || _location != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Selecting a folder checks write access with a tiny temporary file.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: enabled && (_manual || _ready) ? _save : null,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Use this folder'),
          ),
        ],
        if (_saving) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const Text('Checking write access and saving…'),
        ],
        if (_saved)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: const Text(
                'Folder verified and saved. Ready to receive songs.',
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: enabled
                ? (_manual ? () => _load(null) : _editManually)
                : null,
            child: Text(
              _manual ? 'Browse shared folders' : 'Enter path manually',
            ),
          ),
        ),
      ],
    );
  }
}
