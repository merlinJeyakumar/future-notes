import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/widgets/note_replacement_dialog.dart';

NoteImportConflict conflict(bool identical) => NoteImportConflict(
  NoteReference(
    binding: StorageBinding('D:/synthetic-library', 1),
    fileName: 'note_synthetic',
    format: NoteStorageFormat.folder,
    contentPath:
        'D:/synthetic-library/note_synthetic/note_content_synthetic.enc',
    attachmentLocation: 'D:/synthetic-library/note_synthetic/attachments',
  ),
  'Synthetic note',
  true,
  identical: identical,
);

void main() {
  for (final identical in [false, true]) {
    for (final choice in NoteImportDecision.values) {
      testWidgets(
        'conflict identical=$identical returns explicit ${choice.name}',
        (tester) async {
          NoteImportDecision? result;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<NoteImportDecision>(
                      context: context,
                      builder: (_) =>
                          NoteReplacementDialog(conflict: conflict(identical)),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.text('This note already exists'), findsOneWidget);
          expect(
            find.text(
              identical
                  ? 'The imported version is identical.'
                  : 'The imported version has different content.',
            ),
            findsOneWidget,
          );
          for (final label in ['Duplicate', 'Back up & Replace', 'Ignore']) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.tap(
            find.text(switch (choice) {
              NoteImportDecision.duplicate => 'Duplicate',
              NoteImportDecision.replace => 'Back up & Replace',
              NoteImportDecision.ignore => 'Ignore',
            }),
          );
          await tester.pumpAndSettle();
          expect(result, choice);
        },
      );
    }
  }
}
