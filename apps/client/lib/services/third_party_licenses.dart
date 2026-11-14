import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString(
      'assets/licenses/SMB-NOTICE.txt',
    );
    final copying = await rootBundle.loadString('assets/licenses/COPYING');
    final lgpl = await rootBundle.loadString(
      'assets/licenses/LICENCE-LGPL-2.1.txt',
    );
    yield LicenseEntryWithLineBreaks(
      ['libsmb2'],
      '$notice\n\n$copying\n\n$lgpl\n\n'
      'Corresponding source and build scripts: '
      'https://github.com/ales-drnz/libsmb2-scripts/tree/7b6639b5ddc189d478314b9752bbb5dc59f0264f\n'
      'Binaries: https://github.com/ales-drnz/dart_smb2/releases/tag/libsmb2-r11',
    );
    yield LicenseEntryWithLineBreaks([
      'OpenSSL',
    ], await rootBundle.loadString('assets/licenses/LICENSE-OpenSSL.txt'));
  });
}
