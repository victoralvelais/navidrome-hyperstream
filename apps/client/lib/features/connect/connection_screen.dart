import 'package:flutter/material.dart';

import '../../services/account_session.dart';
import '../../services/account_store.dart';
import '../../services/navidrome_client.dart';

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key, required this.session});
  final AccountSession session;

  Future<void> _forget(BuildContext context) async {
    try {
      await session.disconnect();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not remove your saved account. Please try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.graphic_eq,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Hyperstream',
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your library, wherever you listen.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (session.savedServers.isNotEmpty &&
                      session.phase != AccountPhase.restoring) ...[
                    for (final server in session.savedServers)
                      ListTile(
                        title: Text(server.displayName),
                        subtitle: Text(server.username),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: session.busy
                            ? null
                            : () => session.switchServer(server.id),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (session.phase == AccountPhase.restoring) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 20),
                    const Text(
                      'Restoring your connection…',
                      textAlign: TextAlign.center,
                    ),
                  ] else if (session.phase == AccountPhase.recovery) ...[
                    Text(
                      'Reconnect to Navidrome',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (session.username != null) ...[
                      const SizedBox(height: 12),
                      Text(session.username!),
                      Text(session.serverUrl!),
                    ],
                    const SizedBox(height: 16),
                    Text(session.error ?? 'Could not restore your connection.'),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: session.busy ? null : session.restore,
                      child: const Text('Retry connection'),
                    ),
                    if (session.canEditConnection)
                      TextButton(
                        onPressed: session.busy ? null : session.editConnection,
                        child: const Text('Edit connection'),
                      ),
                    TextButton(
                      onPressed: session.busy ? null : () => _forget(context),
                      child: const Text('Forget saved account'),
                    ),
                  ] else ...[
                    ServerSignInForm(
                      key: ValueKey((session.serverUrl, session.username)),
                      session: session,
                    ),
                    if (session.hasSavedAccount)
                      TextButton(
                        onPressed: session.busy ? null : () => _forget(context),
                        child: const Text('Forget saved account'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ServerSignInForm extends StatefulWidget {
  const ServerSignInForm({
    super.key,
    required this.session,
    this.adding = false,
    this.beforeSwitch,
  });
  final AccountSession session;
  final bool adding;
  final Future<void> Function()? beforeSwitch;
  @override
  State<ServerSignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<ServerSignInForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _server = TextEditingController(
    text:
        (widget.adding ? '' : widget.session.serverUrl) ??
        const String.fromEnvironment('NAVIDROME_URL'),
  );
  late final _username = TextEditingController(
    text: widget.adding ? '' : widget.session.username ?? '',
  );
  final _password = TextEditingController();
  bool _remember = true;

  Future<void> _connect() async {
    if (widget.session.busy || !_form.currentState!.validate()) return;
    await widget.session.connect(
      SavedAccount(
        serverUrl: _server.text,
        username: _username.text,
        password: _password.text,
        name: _name.text.trim(),
      ),
      remember: _remember,
      beforeSwitch: widget.beforeSwitch,
    );
    if (mounted && widget.session.client != null) _password.clear();
  }

  @override
  void dispose() {
    _server.dispose();
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.adding) ...[
            TextFormField(
              controller: _name,
              enabled: !session.busy,
              decoration: const InputDecoration(
                labelText: 'Server name',
                hintText: 'Home library',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _server,
            enabled: !session.busy,
            decoration: const InputDecoration(
              labelText: 'Navidrome server',
              hintText: 'https://music.example.com',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            validator: (value) {
              try {
                NavidromeClient.parseServerUrl(value ?? '');
                return null;
              } on NavidromeException catch (error) {
                return error.message;
              }
            },
          ),
          if (_server.text.trim().toLowerCase().startsWith('http://')) ...[
            const SizedBox(height: 8),
            const Text(
              'HTTP does not encrypt your connection. Use HTTPS outside your trusted network.',
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _username,
            enabled: !session.busy,
            decoration: const InputDecoration(labelText: 'Username'),
            autocorrect: false,
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter your username.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            enabled: !session.busy,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            onFieldSubmitted: (_) => _connect(),
            validator: (value) =>
                value == null || value.isEmpty ? 'Enter your password.' : null,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep me signed in'),
            subtitle: Text(
              _remember
                  ? 'Save this account in your device’s secure storage.'
                  : 'Use this account until you close the app.',
            ),
            value: _remember,
            onChanged: session.busy
                ? null
                : (value) => setState(() => _remember = value),
          ),
          if (session.error != null) ...[
            const SizedBox(height: 16),
            Text(
              session.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: session.busy ? null : _connect,
            child: Text(session.busy ? 'Connecting…' : 'Connect'),
          ),
        ],
      ),
    );
  }
}
