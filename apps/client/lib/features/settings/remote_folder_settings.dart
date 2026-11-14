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
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  String? _message;
  bool _failed = false;

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
    final saved = _remote.destination;
    _name.text = saved?.name ?? '';
    _address.text = saved?.address ?? '';
    _username.text = saved?.username ?? '';
    _password.text = saved?.password ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    if (_remote.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _message = null;
      _failed = false;
    });
    try {
      final destination = RemoteDestination(
        address: _address.text,
        username: _username.text,
        password: _password.text,
        name: _name.text,
      );
      await _remote.testAndSave(destination);
      if (mounted) {
        setState(
          () => _message =
              'Connected and saved. You can now send songs to ${destination.displayName}.',
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _message = remoteFolderError(e);
          _failed = true;
        });
      }
    }
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('Forget remote folder?'),
        content: const Text(
          'Remove this saved login from Hyperstream. Files on the server stay where they are.',
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
      _name.clear();
      _address.clear();
      _username.clear();
      _password.clear();
      setState(() {
        _message = 'Remote folder forgotten.';
        _failed = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _message = remoteFolderError(e);
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect directly to a shared folder on your computer or NAS. Use the same server and login you use for file sharing.',
          ),
          const SizedBox(height: 16),
          GlassSurface(
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      enabled: enabled,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                        hintText: 'My test folder',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _address,
                      enabled: enabled,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Server and folder',
                        hintText: 'smb://server/share/Test',
                        helperText: 'Include the share and an existing folder.',
                      ),
                      validator: (value) => value?.trim().isEmpty != false
                          ? 'Enter a shared folder address.'
                          : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _username,
                      enabled: enabled,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: r'COMPUTER\username',
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
                      obscureText: _hidden,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
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
                      onFieldSubmitted: enabled ? (_) => _save() : null,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Test and save creates and removes a tiny test file in this folder. Your login is saved securely on this device.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: enabled ? _save : null,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Test and save'),
                    ),
                    if (_remote.busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Connecting… Keep Hyperstream open.'),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _message!,
                style: _failed
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
          if (_remote.destination != null)
            TextButton(
              onPressed: enabled ? _forget : null,
              child: const Text('Forget remote folder'),
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
