import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/import_confirmation_dialog.dart';

void main() {
  group('ImportConfirmationDialog Widget Tests', () {
    testWidgets('renders correctly with basic info', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportConfirmationDialog(
              fileName: 'test_note.fnote',
              fileType: 'Binary Pack',
            ),
          ),
        ),
      );

      // Verify title
      expect(find.text('Import File'), findsOneWidget);

      // Verify file info
      expect(find.text('File: test_note.fnote'), findsOneWidget);
      expect(find.text('Type: Binary Pack'), findsOneWidget);

      // Verify buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('renders correctly with preview info', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportConfirmationDialog(
              fileName: 'test_note.enc',
              fileType: 'Encrypted Note',
              previewInfo: 'Title: My Note\nDate: 2024-01-15',
            ),
          ),
        ),
      );

      // Verify preview details section
      expect(find.text('Preview Details:'), findsOneWidget);
      expect(find.text('Title: My Note\nDate: 2024-01-15'), findsOneWidget);
    });

    testWidgets('does not show preview section when previewInfo is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportConfirmationDialog(
              fileName: 'test_note.txt',
              fileType: 'Plain Text',
            ),
          ),
        ),
      );

      // Verify no preview section
      expect(find.text('Preview Details:'), findsNothing);
    });

    testWidgets('cancel button returns false', (WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const ImportConfirmationDialog(
                      fileName: 'test.fnote',
                      fileType: 'Binary Pack',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify result
      expect(result, false);
    });

    testWidgets('import button returns true', (WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const ImportConfirmationDialog(
                      fileName: 'test.fnote',
                      fileType: 'Binary Pack',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Import
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // Verify result
      expect(result, true);
    });

    testWidgets('displays long file names correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportConfirmationDialog(
              fileName:
                  'this_is_a_very_long_file_name_that_should_still_display.fnote',
              fileType: 'Binary Pack',
            ),
          ),
        ),
      );

      expect(
        find.text(
          'File: this_is_a_very_long_file_name_that_should_still_display.fnote',
        ),
        findsOneWidget,
      );
    });

    testWidgets('different file types display correctly', (
      WidgetTester tester,
    ) async {
      for (final fileType in [
        'Plain Text',
        'Encrypted Note',
        'ZIP Archive',
        'Binary Pack',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ImportConfirmationDialog(
                fileName: 'test.file',
                fileType: fileType,
              ),
            ),
          ),
        );

        expect(find.text('Type: $fileType'), findsOneWidget);

        // Need to pump new widget for next iteration
        await tester.pumpAndSettle();
      }
    });
  });
}
