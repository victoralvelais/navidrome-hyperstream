import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/remote_folder.dart';
import '../../widgets/glass_overlays.dart';
import '../../widgets/glass_surface.dart';

class RemoteFolderSettings extends StatefulWidget {
  const RemoteFolderSettings({super.key, this.remote});
  final RemoteFolders? remote;
  @override
  State<RemoteFolderSettings> createState() => _RemoteFolderSettingsState();
}

class _RemoteFolderSettingsState extends State<RemoteFolderSettings> {
  late final RemoteFolders _remote = widget.remote ?? RemoteFolders.instance;
  final _loginForm = GlobalKey<FormState>();
  final _folderForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _share = TextEditingController();
  final _folder = TextEditingController();
  bool _hidden = true;
  RemoteConnection? _verified;
  String? _loginMessage;
  bool _loginFailed = false;
  String? _folderMessage;
  bool _folderFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool retry = false}) async {
    if (retry) {
      await _remote.retryRestore();
    } else {
      await _remote.restore();
    }
    if (!mounted) return;
    final saved = _remote.connection;
    _name.text = saved?.name ?? '';
    _address.text = saved?.address ?? '';
    _username.text = saved?.username ?? '';
    _password.text = saved?.password ?? '';
    _share.text = _remote.destination?.share ?? '';
    _folder.text = _remote.destination?.folder ?? '';
    setState(() {});
  }

  void _loginChanged(String _) => setState(() {
    _verified = null;
    _loginMessage = null;
    _folderMessage = null;
  });

  Future<void> _checkConnection() async {
    if (_remote.busy || !_loginForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _verified = null;
      _loginMessage = null;
      _folderMessage = null;
      _loginFailed = false;
    });
    try {
      final connection = RemoteConnection(
        address: _address.text,
        username: _username.text,
        password: _password.text,
        name: _name.text,
      );
      final previous = _remote.connection;
      await _remote.checkAndSaveConnection(connection);
      if (!mounted) return;
      if (previous != null && !previous.sameAccount(connection)) {
        _share.clear();
        _folder.clear();
      }
      setState(() {
        _verified = connection;
        _hidden = true;
        _loginMessage =
            'Login verified over encrypted SMB. Saved securely on this device.';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loginFailed = true;
        _loginMessage =
            e is RemoteCheckException && e.stage == RemoteCheckStage.save
            ? 'Login verified. ${remoteFolderError(e)}'
            : remoteFolderError(e);
      });
    }
  }

  Future<void> _saveFolder() async {
    final connection = _verified;
    if (connection == null ||
        _remote.busy ||
        !_folderForm.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _folderMessage = null;
      _folderFailed = false;
    });
    try {
      final destination = connection.destination(
        share: _share.text,
        folder: _folder.text,
      );
      await _remote.testAndSave(destination);
      if (!mounted) return;
      setState(
        () => _folderMessage =
            'Folder verified and saved. Ready to receive songs.',
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _folderFailed = true;
        final stage = e is RemoteCheckException
            ? switch (e.stage) {
                RemoteCheckStage.share => 'Share check failed. ',
                RemoteCheckStage.folder => 'Folder check failed. ',
                RemoteCheckStage.write => 'Write check failed. ',
                RemoteCheckStage.save => 'Folder verified. ',
                RemoteCheckStage.login => '',
              }
            : '';
        _folderMessage = '$stage${remoteFolderError(e)}';
      });
    }
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('Forget remote connection?'),
        content: const Text(
          'Remove this server login and folder selection from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _remote.busy) return;
    try {
      await _remote.forget();
      if (!mounted) return;
      for (final controller in [
        _name,
        _address,
        _username,
        _password,
        _share,
        _folder,
      ]) {
        controller.clear();
      }
      setState(() {
        _verified = null;
        _hidden = true;
        _loginMessage = null;
        _folderMessage = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loginMessage = remoteFolderError(e);
        _loginFailed = true;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _username,
      _password,
      _share,
      _folder,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _status(String message, {bool failed = false}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: failed
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
    ),
  );

  Widget _card(List<Widget> children) => GlassSurface(
    radius: 24,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _progress() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        _status(switch (_remote.checking!) {
          RemoteCheckStage.login => 'Checking server login…',
          RemoteCheckStage.share => 'Opening the share…',
          RemoteCheckStage.folder => 'Checking the folder…',
          RemoteCheckStage.write => 'Checking write access…',
          RemoteCheckStage.save => 'Saving securely on this device…',
        }),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _remote,
    builder: (context, _) {
      if (!_remote.loaded) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_remote.error != null) {
        return Column(
          children: [
            Text(_remote.error!),
            TextButton(
              onPressed: () => _load(retry: true),
              child: const Text('Try again'),
            ),
          ],
        );
      }
      final enabled = !_remote.busy;
      final folderEnabled = enabled && _verified != null;
      final titleStyle = Theme.of(context).textTheme.titleLarge;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card([
            Row(
              children: [
                Icon(
                  _verified == null
                      ? Icons.dns_outlined
                      : Icons.check_circle_outline_rounded,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _verified == null ? 'Server connection' : 'Login verified',
                    style: titleStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_verified != null) ...[
              Text(
                _verified!.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_verified!.address),
              if (_loginMessage != null)
                _status(_loginMessage!, failed: _loginFailed),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: enabled ? () => _loginChanged('') : null,
                  child: const Text('Edit or recheck connection'),
                ),
              ),
            ] else
              Form(
                key: _loginForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _remote.connection == null
                          ? 'Check your server login first. Choose the shared folder afterward.'
                          : 'Your login is saved. Check the connection to choose or change its folder.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _name,
                      enabled: enabled,
                      onChanged: _loginChanged,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                        hintText: 'Music server',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _address,
                      enabled: enabled,
                      onChanged: _loginChanged,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Server address',
                        hintText: 'smb://computer',
                        helperText: 'Server name or IP address. Choose the share below.',
                        helperMaxLines: 4,
                      ),
                      validator: (value) => value?.trim().isEmpty != false
                          ? 'Enter the server name or IP address.'
                          : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _username,
                      enabled: enabled,
                      onChanged: _loginChanged,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: r'COMPUTER\username',
                        helperText: r'COMPUTER\username or COMPUTER/username both work.',
                        helperMaxLines: 4,
                      ),
                      validator: (value) => value?.trim().isEmpty != false
                          ? 'Enter your file-sharing username.'
                          : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: enabled,
                      onChanged: _loginChanged,
                      obscureText: _hidden,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'Use the account password. Windows PINs cannot sign in here.',
                        helperMaxLines: 4,
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Show password' : 'Hide password',
                          onPressed: enabled
                              ? () => setState(() => _hidden = !_hidden)
                              : null,
                          icon: Icon(
                            _hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value?.isEmpty != false
                          ? 'Enter your file-sharing password.'
                          : null,
                      onFieldSubmitted: enabled
                          ? (_) => _checkConnection()
                          : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: enabled ? _checkConnection : null,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: const Text('Check connection'),
                    ),
                    if (_loginMessage != null)
                      _status(_loginMessage!, failed: _loginFailed),
                    if (_remote.checking != null) _progress(),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: 16),
          _card([
            Text('Destination folder', style: titleStyle),
            const SizedBox(height: 12),
            if (_verified == null)
              const Text(
                'Verify your server login above to set up the folder.',
              ),
            if (_remote.destination != null) ...[
              Text(
                'Saved folder',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(_remote.destination!.address),
            ],
            const SizedBox(height: 16),
            Form(
              key: _folderForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _share,
                    enabled: folderEnabled,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _folderMessage = null),
                    decoration: const InputDecoration(
                      labelText: 'Share name',
                      hintText: 'Music',
                      helperText: 'The shared name shown in Windows Sharing properties.',
                      helperMaxLines: 4,
                    ),
                    validator: (value) => value?.trim().isEmpty != false
                        ? 'Enter the share name.'
                        : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _folder,
                    enabled: folderEnabled,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _folderMessage = null),
                    decoration: const InputDecoration(
                      labelText: 'Subfolder (optional)',
                      hintText: 'Hyperstream Test',
                      helperText: 'Leave empty to use the share itself. Any subfolder must already exist.',
                      helperMaxLines: 4,
                    ),
                    onFieldSubmitted: folderEnabled
                        ? (_) => _saveFolder()
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This check creates, renames, and removes a tiny test file to verify write access.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: folderEnabled ? _saveFolder : null,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Test and save folder'),
                  ),
                  if (_folderMessage != null)
                    _status(_folderMessage!, failed: _folderFailed),
                  if (_remote.checking != null && _verified != null)
                    _progress(),
                ],
              ),
            ),
          ]),
          if (_remote.connection != null)
            TextButton(
              onPressed: enabled ? _forget : null,
              child: const Text('Forget remote connection'),
            ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Hyperstream',
            ),
            child: const Text('Open-source licenses'),
          ),
        ],
      );
    },
  );
}
