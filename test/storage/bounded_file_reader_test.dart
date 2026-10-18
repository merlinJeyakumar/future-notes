import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/bounded_file_reader.dart';
import '../support/validation_directory.dart';

void main() {
  test(
    'read-only bounded cursors stay independent and reject invalid windows',
    () async {
      final run = await Directory.systemTemp.createTemp(
        'future-notes-validation-',
      );
      try {
        final file = File(p.join(run.path, 'source'));
        await file.writeAsBytes(List.generate(4096, (i) => i % 251));
        final a = await BoundedFileReader.openPath(file.path);
        final b = await BoundedFileReader.openPath(file.path);
        try {
          await a.setPosition(200);
          expect(await a.read(4), [200, 201, 202, 203]);
          expect(await b.read(4), [0, 1, 2, 3]);
          await a.setPosition(4095);
          expect((await a.read(32)).length, 1);
          expect(await a.read(1), isEmpty);
          await expectLater(a.setPosition(4097), throwsFormatException);
          await expectLater(
            a.read(BoundedFileReader.window + 1),
            throwsFormatException,
          );
          expect(() => a.writeFromSync([1]), throwsUnsupportedError);
        } finally {
          await a.close();
          await b.close();
        }
        await expectLater(a.read(1), throwsFormatException);
        expect(await file.length(), 4096);
      } finally {
        await deleteValidationRun(run);
      }
    },
  );
}
