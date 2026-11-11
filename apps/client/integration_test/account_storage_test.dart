import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
        await store.clear();
        expect(await store.read(), isNull);
      } finally {
        await store.clear();
      }
    },
  );
}
