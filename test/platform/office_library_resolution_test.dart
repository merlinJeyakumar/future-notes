import 'package:flutter_application_1/features/dashboard/services/office_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'each native host uses its packaged ABI without changing Windows/Android',
    () {
      final executable = p.join('bundle', 'future_notes');
      expect(
        officePreviewLibrary(
          operatingSystem: 'windows',
          executable: executable,
        ),
        p.join('bundle', 'office_oxide.dll'),
      );
      expect(
        officePreviewLibrary(
          operatingSystem: 'android',
          executable: executable,
        ),
        'liboffice_oxide.so',
      );
      for (final host in ['macos', 'ios']) {
        expect(
          officePreviewLibrary(operatingSystem: host, executable: executable),
          isEmpty,
        );
      }
      expect(
        officePreviewLibrary(operatingSystem: 'linux', executable: executable),
        p.join('bundle', 'lib', 'liboffice_oxide.so'),
      );
      expect(
        () => officePreviewLibrary(
          operatingSystem: 'web',
          executable: executable,
        ),
        throwsUnsupportedError,
      );
    },
  );
}
