import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/remote_folder.dart';
import '../../widgets/glass_overlays.dart';
import '../../widgets/glass_surface.dart';
import 'remote_folder_browser.dart';

class RemoteFolderSettings extends StatefulWidget {
  const RemoteFolderSettings({super.key, this.remote});
  final RemoteFolders? remote;
  @override
  State<RemoteFolderSettings> createState() => _RemoteFolderSettingsState();
}

class _RemoteFolderSettingsState extends State<RemoteFolderSettings> {
  late final RemoteFolders _remote = widget.remote ?? RemoteFolders.instance;
  final _loginForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  RemoteConnection? _connection;
  bool _verified = false;
  String? _loginMessage;
  bool _loginFailed = false;

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
    _connection = saved;
    setState(() {});
  }

  void _loginChanged(String _) => setState(() {
    _connection = null;
    _verified = false;
    _loginMessage = null;
  });

  Future<void> _checkConnection() async {
    if (_remote.busy || !_loginForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _connection = null;
      _verified = false;
      _loginMessage = null;
      _loginFailed = false;
    });
    try {
      final connection = RemoteConnection(
        address: _address.text,
        username: _username.text,
        password: _password.text,
        name: _name.text,
      );
      await _remote.checkAndSaveConnection(connection);
      if (!mounted) return;
      setState(() {
        _connection = connection;
        _verified = true;
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
      for (final controller in [_name, _address, _username, _password]) {
        controller.clear();
      }
      setState(() {
        _connection = null;
        _verified = false;
        _hidden = true;
        _loginMessage = null;
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
    for (final controller in [_name, _address, _username, _password]) {
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
          RemoteCheckStage.shares => 'Finding shared folders…',
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
      final titleStyle = Theme.of(context).textTheme.titleLarge;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card([
            Row(
              children: [
                Icon(
                  _verified
                      ? Icons.check_circle_outline_rounded
                      : Icons.dns_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _connection == null
                        ? 'Server connection'
                        : _verified
                        ? 'Login verified'
                        : 'Saved connection',
                    style: titleStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_connection != null) ...[
              Text(
                _connection!.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_connection!.address),
              _status(
                _loginMessage ?? 'Your login is saved securely on this device.',
                failed: _loginFailed,
              ),
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
                        hintText: 'username',
                        helperText:
                            'Use the username that works for file sharing.',
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
            if (_connection == null)
              const Text('Connect to show the available shared folders.')
            else
              RemoteFolderBrowser(
                key: ObjectKey(_connection),
                remote: _remote,
                connection: _connection!,
                onVerified: () => setState(() => _verified = true),
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
