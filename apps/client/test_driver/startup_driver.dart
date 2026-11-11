import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 2),
  responseDataCallback: (data) async {
    if (data?['startupReachedSignIn'] != true) {
      throw StateError('The app did not report reaching sign-in.');
    }
  },
);
