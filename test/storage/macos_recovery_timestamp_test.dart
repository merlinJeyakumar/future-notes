import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/storage/desktop_posix_native.dart';
import '../support/validation_directory.dart';

void main() {
  test(
    'Mac recovery timestamp preserves fractional seconds and access time',
    () async {
      final run = await createValidationRun();
      try {
        final file = File('${run.path}/candidate.restore');
        final bytes = List<int>.filled(32, 17);
        await file.writeAsBytes(bytes, flush: true);
        final before = await file.stat();
        final wanted = DateTime.utc(
          2026,
          1,
          2,
          3,
          4,
          5,
          972,
        ).microsecondsSinceEpoch;
        DesktopPosixNative().setLastModifiedMicros(file.path, wanted);
        final after = await file.stat();
        expect(after.modified.microsecondsSinceEpoch, wanted);
        expect(after.accessed, before.accessed);
        expect(after.size, before.size);
        expect(await file.readAsBytes(), bytes);
      } finally {
        await deleteValidationRun(run);
      }
    },
    skip: !Platform.isMacOS,
  );
}
