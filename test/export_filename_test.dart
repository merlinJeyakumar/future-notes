import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/export_filename.dart';

void main() {
  test(
    'export filenames retain titles, Unicode and the correct single extension',
    () {
      expect(noteExportFileName('Ave maria', 'fnote'), 'Ave maria.fnote');
      expect(noteExportFileName('  Report.FNOTE  ', 'zip'), 'Report.zip');
      expect(
        noteExportFileName('தமிழ் العربية 😀', 'fnote'),
        'தமிழ் العربية 😀.fnote',
      );
      expect(noteExportFileName(' .. ', 'zip'), 'Untitled note.zip');
      expect(
        noteExportFileName('..A/B\\C: D?*<>|". ', 'fnote'),
        'A-B-C- D------.fnote',
      );
      expect(noteExportFileName('CON.txt', 'zip'), 'Note - CON.txt.zip');
      expect(noteExportFileName('lpt9', 'fnote'), 'Note - lpt9.fnote');
      expect(noteExportFileName('A\nB\u0000 C\u202e', 'zip'), 'A B C.zip');
      final long = noteExportFileName('😀' * 100, 'fnote');
      expect(utf8.encode(long).length, lessThanOrEqualTo(186));
      expect(long.endsWith('.fnote'), isTrue);
      expect(long.contains('\uFFFD'), isFalse);
      expect(() => noteExportFileName('Note', '../bad'), throwsArgumentError);
    },
  );
}
