import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/password_dialog.dart';

void main() {
  for (final mode in PasswordMode.values) {
    testWidgets('$mode accepts typing immediately when prompted', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PasswordDialog(mode: mode, onConfirm: (_) {}),
                ),
                child: const Text('Prompt'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prompt'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      expect(fields.first.focusNode.hasFocus, isTrue);
      expect(fields.skip(1).any((field) => field.focusNode.hasFocus), isFalse);
      tester.testTextInput.enterText('synthetic-password');
      await tester.pump();
      expect(fields.first.controller.text, 'synthetic-password');
    });
  }

  group('PasswordDialog Widget Tests', () {
    testWidgets('renders unlock mode correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(mode: PasswordMode.unlock, onConfirm: (_) {}),
          ),
        ),
      );

      // Verify title
      expect(find.text('Unlock Note'), findsOneWidget);
      expect(find.text('Enter password to unlock this note.'), findsOneWidget);

      // Verify single password field
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsNothing);

      // Verify buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
    });

    testWidgets('renders set password mode correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(mode: PasswordMode.set, onConfirm: (_) {}),
          ),
        ),
      );

      // Verify title
      expect(find.text('Set Password'), findsOneWidget);
      expect(
        find.text('Enter a new password to protect this note.'),
        findsOneWidget,
      );

      // Verify password fields
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Verify buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('renders update password mode correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(mode: PasswordMode.update, onConfirm: (_) {}),
          ),
        ),
      );

      // Verify title
      expect(find.text('Update Password'), findsOneWidget);
      expect(
        find.text('Enter your current password and a new password.'),
        findsOneWidget,
      );

      // Verify all three password fields
      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Verify buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows error when passwords do not match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(mode: PasswordMode.set, onConfirm: (_) {}),
          ),
        ),
      );

      // Enter mismatched passwords
      await tester.enterText(find.byType(TextField).first, 'password123');
      await tester.enterText(find.byType(TextField).last, 'different123');

      // Tap Save button
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify error message
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('shows error when password is too short', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(mode: PasswordMode.set, onConfirm: (_) {}),
          ),
        ),
      );

      // Enter short password
      await tester.enterText(find.byType(TextField).first, '123');
      await tester.enterText(find.byType(TextField).last, '123');

      // Tap Save button
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify error message
      expect(
        find.text('Password must be at least 4 characters'),
        findsOneWidget,
      );
    });

    testWidgets('toggles password visibility', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(mode: PasswordMode.unlock, onConfirm: (_) {}),
          ),
        ),
      );

      // Password should be obscured by default
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.obscureText, isTrue);

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();

      // Password should now be visible
      final updatedTextField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(updatedTextField.obscureText, isFalse);
    });

    testWidgets('calls onConfirm with correct password on successful submit', (
      WidgetTester tester,
    ) async {
      String? confirmedPassword;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => PasswordDialog(
                      mode: PasswordMode.set,
                      onConfirm: (password) {
                        confirmedPassword = password;
                      },
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

      // Enter matching passwords
      await tester.enterText(
        find.widgetWithText(TextField, 'New Password'),
        'testpass123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        'testpass123',
      );

      // Tap Save button
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify callback was called with correct password
      expect(confirmedPassword, equals('testpass123'));
    });

    testWidgets('cancel button closes dialog without callback', (
      WidgetTester tester,
    ) async {
      bool callbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => PasswordDialog(
                      mode: PasswordMode.unlock,
                      onConfirm: (_) {
                        callbackCalled = true;
                      },
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

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify dialog is closed and callback was not called
      expect(find.text('Unlock Note'), findsNothing);
      expect(callbackCalled, isFalse);
    });

    testWidgets('shows error on incorrect current password in update mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordDialog(
              mode: PasswordMode.update,
              onConfirm: (_) {},
              onVerifyCurrent: (password) async {
                return password == 'correct123';
              },
            ),
          ),
        ),
      );

      // Find text fields by their labels
      final currentPasswordField = find.widgetWithText(
        TextField,
        'Current Password',
      );
      final newPasswordField = find.widgetWithText(TextField, 'New Password');
      final confirmPasswordField = find.widgetWithText(
        TextField,
        'Confirm Password',
      );

      // Enter incorrect current password and new passwords
      await tester.enterText(currentPasswordField, 'wrongpassword');
      await tester.enterText(newPasswordField, 'newpass123');
      await tester.enterText(confirmPasswordField, 'newpass123');

      // Tap Save button
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify error message
      expect(find.text('Incorrect current password'), findsOneWidget);
    });

    testWidgets('successful update with correct current password', (
      WidgetTester tester,
    ) async {
      String? newPassword;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => PasswordDialog(
                      mode: PasswordMode.update,
                      onConfirm: (password) {
                        newPassword = password;
                      },
                      onVerifyCurrent: (password) async {
                        return password == 'oldpass123';
                      },
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

      // Find text fields by their labels
      final currentPasswordField = find.widgetWithText(
        TextField,
        'Current Password',
      );
      final newPasswordField = find.widgetWithText(TextField, 'New Password');
      final confirmPasswordField = find.widgetWithText(
        TextField,
        'Confirm Password',
      );

      // Enter correct current password and new passwords
      await tester.enterText(currentPasswordField, 'oldpass123');
      await tester.enterText(newPasswordField, 'newpass456');
      await tester.enterText(confirmPasswordField, 'newpass456');

      // Tap Save button
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify callback was called with new password
      expect(newPassword, equals('newpass456'));
    });
  });
}
