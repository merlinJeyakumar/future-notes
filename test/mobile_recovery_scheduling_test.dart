import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/mobile_draft_binding.dart';
import 'package:flutter_application_1/features/dashboard/models/auto_save_policy.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'private recovery captures real revisions, not selection/progress/lifecycle repeats',
    (tester) async {
      final h = await EditorHarness.create(
        autoSavePolicy: AutoSavePolicy.mobile,
      );
      addTearDown(h.dispose);
      h.seed('demo', h.note('demo', 'Synthetic body'));
      await h.editor.loadNote('demo');
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: SizedBox(key: key)));
      final calls = <String>[];
      const channel = MethodChannel('future_notes/private_drafts');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final binding = MobileDraftBinding(
        model: h.editor,
        library: 'synthetic',
        context: () => key.currentContext!,
        onRecovered: () {},
      );
      await binding.restored;
      h.editor.titleController.text = 'Edited title';
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump();
      expect(calls.where((call) => call == 'write'), hasLength(1));
      h.editor.quillController.updateSelection(
        const TextSelection.collapsed(offset: 2),
        ChangeSource.local,
      );
      h.editor.notifyListeners();
      await tester.pump(const Duration(seconds: 1));
      await binding.flush();
      binding.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(calls.where((call) => call == 'write'), hasLength(1));
      expect(h.files.writeAttempts, 0);
      expect((await h.editor.saveNote()).isSuccess, true);
      await tester.pump(const Duration(milliseconds: 750));
      expect(calls.where((call) => call == 'discard'), hasLength(1));
      await binding.flush();
      expect(calls.where((call) => call == 'discard'), hasLength(1));
      binding.dispose();
      h.disposeEditor();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
