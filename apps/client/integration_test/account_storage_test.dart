import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows output bridge enumerates devices and rejects missing ones',
    (tester) async {
      if (defaultTargetPlatform != TargetPlatform.windows) return;
      const channel = MethodChannel('dev.hyperstream/audio_outputs');
      final outputs = await channel.invokeListMethod<Object?>('getOutputs');
      expect(outputs, isNotEmpty);
      expect((outputs!.first as Map)['id'], '');
      await channel.invokeMethod<void>('setOutput', '');
      await expectLater(
        channel.invokeMethod<void>(
          'setOutput',
          'hyperstream-nonexistent-synthetic-output',
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  testWidgets(
    'native protected storage survives a new store and deletes only its record',
    (tester) async {
      // Separate key: never read, overwrite, or delete the user's real account.
      const key = 'hyperstream.integration.account-storage.v1';
      const store = SecureAccountStore(key: key);
      final account = SavedAccount(
        serverUrl: 'https://example.invalid',
        username: 'synthetic-probe',
        password: 'synthetic-probe-secret',
      );
      try {
        await store.save(account);
        final restored = await const SecureAccountStore(key: key).read();
        expect(restored?.serverUrl, account.serverUrl);
        expect(restored?.username, account.username);
        expect(restored?.password, account.password);
        final second = SavedAccount(
          serverUrl: 'https://second.invalid',
          username: 'synthetic-second',
          password: 'synthetic-second-secret',
        );
        await store.saveServers(
          SavedServers(accounts: [account, second], activeId: second.id),
        );
        final servers = await const SecureAccountStore(key: key).readServers();
        expect(servers.accounts, hasLength(2));
        expect(servers.active!.password, second.password);
        await store.clear();
        expect(await store.read(), isNull);
      } finally {
        await store.clear();
      }
    },
  );
}
