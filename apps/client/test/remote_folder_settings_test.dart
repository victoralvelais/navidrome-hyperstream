import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/settings/remote_folder_settings.dart';
import 'package:hyperstream_client/services/remote_folder.dart';

import 'remote_folder_test.dart' show MemoryRemoteStore, MemoryRemoteFs;

void main() {
  testWidgets('direct SMB form tests and saves without opening Files', (
    tester,
  ) async {
    final store = MemoryRemoteStore();
    final fs = MemoryRemoteFs();
    final remote = RemoteFolders(store: store, connect: (_) async => fs);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteFolderSettings(remote: remote),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test folder');
    await tester.enterText(fields.at(1), 'smb://server/share/Test');
    await tester.enterText(fields.at(2), r'KIRA\Listener');
    await tester.enterText(fields.at(3), 'private-password');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(3)).obscureText,
      isTrue,
    );
    await tester.ensureVisible(find.text('Test and save'));
    await tester.tap(find.text('Test and save'));
    await tester.pumpAndSettle();
    expect(store.value?.address, 'smb://server/share/Test');
    expect(store.value?.password, 'private-password');
    expect(fs.files, isEmpty);
    expect(find.textContaining('Connected and saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    remote.dispose();
  });
}
