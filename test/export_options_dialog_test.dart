import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/export_options_dialog.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';

void main() {
  group('ExportOptionsDialog Widget Tests', () {
    testWidgets('renders correctly without attachments', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExportOptionsDialog(hasAttachments: false)),
        ),
      );

      // Verify title
      expect(find.text('Export Options'), findsOneWidget);

      // Verify format options
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Binary Pack (.fnote)'), findsOneWidget);
      expect(find.text('ZIP Archive (.zip)'), findsOneWidget);

      // Verify password protection toggle
      expect(find.text('Password Protection'), findsOneWidget);

      // Verify buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);

      // Verify no attachments info shown
      expect(
        find.text(
          'This note has attachments. They will be included in the export.',
        ),
        findsNothing,
      );
    });

    testWidgets('shows attachments info when hasAttachments is true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExportOptionsDialog(hasAttachments: true)),
        ),
      );

      expect(
        find.text(
          'This note has attachments. They will be included in the export.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('binary format is selected by default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExportOptionsDialog(hasAttachments: false)),
        ),
      );

      // Binary format should be selected
      final binaryRadio = tester.widget<Radio<ExportFormat>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Radio<ExportFormat> &&
              widget.value == ExportFormat.binary,
        ),
      );
      expect(binaryRadio.groupValue, ExportFormat.binary);
    });

    testWidgets('can switch to ZIP format', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExportOptionsDialog(hasAttachments: false)),
        ),
      );

      // Tap on ZIP option
      await tester.tap(find.text('ZIP Archive (.zip)'));
      await tester.pumpAndSettle();

      // ZIP format should now be selected
      final zipRadio = tester.widget<Radio<ExportFormat>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Radio<ExportFormat> && widget.value == ExportFormat.zip,
        ),
      );
      expect(zipRadio.groupValue, ExportFormat.zip);
    });

    testWidgets('password fields appear when toggle is enabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExportOptionsDialog(hasAttachments: false)),
        ),
      );

      // Password fields should not be visible initially
      expect(find.widgetWithText(TextField, 'Password'), findsNothing);

      // Toggle password protection on
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Password fields should now be visible
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Confirm Password'),
        findsOneWidget,
      );
      final password = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(password.focusNode.hasFocus, isTrue);
      tester.testTextInput.enterText('synthetic-export-password');
      await tester.pump();
      expect(password.controller.text, 'synthetic-export-password');
    });

    testWidgets('shows error when passwords do not match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        const ExportOptionsDialog(hasAttachments: false),
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

      // Enable password protection
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Enter mismatched passwords
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        'different123',
      );

      // Tap Export
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify error
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('shows error when password is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        const ExportOptionsDialog(hasAttachments: false),
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

      // Enable password protection
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Tap Export without entering password
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify error
      expect(find.text('Password cannot be empty'), findsOneWidget);
    });

    testWidgets('shows error when password is too short', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        const ExportOptionsDialog(hasAttachments: false),
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

      // Enable password protection
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Enter short password
      await tester.enterText(find.widgetWithText(TextField, 'Password'), '123');
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        '123',
      );

      // Tap Export
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify error
      expect(
        find.text('Password must be at least 4 characters'),
        findsOneWidget,
      );
    });

    testWidgets('returns ExportOptions on successful export without password', (
      WidgetTester tester,
    ) async {
      ExportOptions? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ExportOptions>(
                    context: context,
                    builder: (_) =>
                        const ExportOptionsDialog(hasAttachments: false),
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

      // Tap Export (binary format selected by default, no password)
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify result
      expect(result, isNotNull);
      expect(result!.format, ExportFormat.binary);
      expect(result!.password, isNull);
    });

    testWidgets('returns ExportOptions with password when provided', (
      WidgetTester tester,
    ) async {
      ExportOptions? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ExportOptions>(
                    context: context,
                    builder: (_) =>
                        const ExportOptionsDialog(hasAttachments: false),
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

      // Select ZIP format
      await tester.tap(find.text('ZIP Archive (.zip)'));
      await tester.pumpAndSettle();

      // Enable password protection
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Enter matching passwords
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'mypassword123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        'mypassword123',
      );

      // Tap Export
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify result
      expect(result, isNotNull);
      expect(result!.format, ExportFormat.zip);
      expect(result!.password, 'mypassword123');
    });

    testWidgets('cancel button closes dialog without result', (
      WidgetTester tester,
    ) async {
      ExportOptions? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ExportOptions>(
                    context: context,
                    builder: (_) =>
                        const ExportOptionsDialog(hasAttachments: false),
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

      // Verify dialog closed with no result
      expect(find.text('Export Options'), findsNothing);
      expect(result, isNull);
    });
  });
}
