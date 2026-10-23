import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/mobile_draft_binding.dart';
import 'package:flutter_application_1/features/dashboard/models/auto_save_policy.dart';
import 'package:flutter_application_1/features/dashboard/widgets/password_dialog.dart';
import 'support/editor_harness.dart';

void main() {
  const channel = MethodChannel('future_notes/private_drafts');

  Map<String, dynamic> draft(EditorHarness h) => {
    'version': 1,
    'id': 'synthetic-recovery',
    'fileName': null,
    'title': 'Recovered synthetic draft',
    'timestamp': 1700000000000,
    'html': false,
    'protected': true,
    'metadata': <String, dynamic>{},
    'attachments': <dynamic>[],
    'fields': ['body'],
    'body': h.encryption.wrapUser('Recovered body', 'synthetic-password'),
  };

  for (final action in ['recover', 'cancel', 'back', 'conflict']) {
    testWidgets('protected recovery $action prompts once and retains safety', (
      tester,
    ) async {
      final h = await EditorHarness.create(
        autoSavePolicy: AutoSavePolicy.mobile,
      );
      final payload = draft(h);
      if (action == 'conflict') {
        payload['fileName'] = 'missing-note';
        payload['base'] = {'sha256': 'old', 'length': 123};
      }
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'read' ? jsonEncode(payload) : null;
      });
      final key = GlobalKey();
      var recovered = 0;
      MobileDraftBinding? binding;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SizedBox(key: key)),
          ),
        );
        binding = MobileDraftBinding(
          model: h.editor,
          library: 'synthetic-library',
          context: () => key.currentContext!,
          onRecovered: () => recovered++,
        );
        await tester.pumpAndSettle();
        expect(find.text('Recover unsaved draft?'), findsOneWidget);
        if (action == 'back') {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('Recover'));
          await tester.pumpAndSettle();
          expect(find.text('Recover unsaved draft?'), findsNothing);
          expect(find.text('Unlock recovery draft'), findsOneWidget);
          if (action == 'cancel') {
            await tester.tap(find.text('Cancel'));
          } else {
            await tester.enterText(
              find.byType(TextField),
              'synthetic-password',
            );
            final paused = PausePoint();
            h.encryption.nextDecryption = paused;
            final submit = tester
                .widget<TextField>(find.byType(TextField))
                .onSubmitted!;
            submit('synthetic-password');
            submit('synthetic-password');
            await tester.pump();
            binding.didChangeAppLifecycleState(AppLifecycleState.inactive);
            binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
            paused.resume();
          }
        }
        await tester.pumpAndSettle();
        if (action == 'conflict') {
          expect(find.text('Recovery retained'), findsOneWidget);
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
        }
        await binding.restored;
        expect(find.text('Unlock recovery draft'), findsNothing);
        expect(find.text('Recover unsaved draft?'), findsNothing);
        expect(find.text('Recovery retained'), findsNothing);
        expect(recovered, action == 'recover' ? 1 : 0);
        expect(calls.where((call) => call == 'read'), hasLength(1));
        if (action == 'recover') {
          expect(h.editor.titleController.text, 'Recovered synthetic draft');
          expect(
            h.editor.quillController.document.toPlainText(),
            'Recovered body\n',
          );
          expect(h.editor.currentFileName, isNull);
          expect(h.editor.draftSession.isDirty, isTrue);
        } else {
          h.editor.titleController.text = 'Continue normal editing';
          binding.didChangeAppLifecycleState(AppLifecycleState.inactive);
          await binding.flush();
          await binding.retireResolvedDraft();
          await tester.pump(const Duration(seconds: 1));
          expect(
            calls.where((call) => call == 'write' || call == 'discard'),
            isEmpty,
          );
          expect(h.editor.currentFileName, isNull);
        }
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        binding?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      }
    });
  }

  testWidgets(
    'mobile password submission verifies once and keeps the underlying route',
    (tester) async {
      final verify = Completer<bool>();
      var calls = 0;
      var confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => PasswordDialog(
                    preventDuplicateSubmissions: true,
                    onConfirm: (_) => confirmed++,
                    onVerifyCurrent: (_) {
                      calls++;
                      return verify.future;
                    },
                  ),
                ),
                child: const Text('Underlying route'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Underlying route'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'synthetic-password');
      final submit = tester
          .widget<TextField>(find.byType(TextField))
          .onSubmitted!;
      submit('synthetic-password');
      submit('synthetic-password');
      expect(calls, 1);
      verify.complete(true);
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(find.text('Underlying route'), findsOneWidget);
      expect(find.byType(PasswordDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
