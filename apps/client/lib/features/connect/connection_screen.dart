import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';

typedef ClientFactory = NavidromeClient Function({
  required String serverUrl,
  required String username,
  required String password,
});

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.onConnected,
    this.createClient = NavidromeClient.new,
  });

  final ValueChanged<NavidromeClient> onConnected;
  final ClientFactory createClient;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController(
    text: const String.fromEnvironment('NAVIDROME_URL'),
  );
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    NavidromeClient? client;
    try {
      client = widget.createClient(
        serverUrl: _server.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );
      await client.ping();
      if (!mounted) {
        client.close();
        return;
      }
      _password.clear();
      widget.onConnected(client);
    } on NavidromeException catch (error) {
      client?.close();
      if (mounted) setState(() => _error = error.message);
    } on Object {
      client?.close();
      if (mounted) {
        setState(() => _error = 'Could not connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
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
                  const SizedBox(height: 36),
                  TextFormField(
                    controller: _server,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Navidrome server',
                      hintText: 'https://music.example.com',
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      try {
                        NavidromeClient.parseServerUrl(value ?? '');
                        return null;
                      } on NavidromeException catch (error) {
                        return error.message;
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    enabled: !_busy,
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
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    onFieldSubmitted: (_) => _connect(),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your password.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sign-in lasts until you disconnect or close the app.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      semanticsLabel: _error,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: Text(_busy ? 'Connecting…' : 'Connect'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
