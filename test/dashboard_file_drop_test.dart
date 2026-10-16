import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';
import 'package:flutter_application_1/main.dart';
import 'support/validation_directory.dart';

Future<void> settleWork(WidgetTester tester, bool Function() done) async {
  for (var turn = 0; turn < 300 && !done(); turn++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
  expect(done(), isTrue, reason: 'Synthetic drop operation did not settle.');
}

Future<T> joinWork<T>(WidgetTester tester, Future<T> work) async {
  var settled = false;
  work.then<void>(
    (_) {
      settled = true;
    },
    onError: (Object _, StackTrace _) {
      settled = true;
    },
  );
  await settleWork(tester, () => settled);
  return await work;
}

void main() {
  void scenario(
    String name,
    Future<void> Function(WidgetTester, Directory, ContentViewModel) body,
  ) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final run = Directory.systemTemp.createTempSync(
        'future-notes-validation-',
      );
      final app = OwnedAppServices(
        environment: StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: p.join(run.path, 'library'),
          settingsFile: p.join(run.path, 'configuration', 'settings.json'),
        ),
      );
      ContentViewModel? editor;
      try {
        await tester.runAsync(() async {
          expect((await app.initialize()).isSuccess, isTrue);
        });
        await tester.pumpWidget(
          MyApp(
            settings: app.settings,
            home: DashboardScreen(
              settings: app.settings,
              fileService: app.files,
              startBackgroundServices: false,
            ),
          ),
        );
        await tester.pump();
        editor = tester.widget<ContentArea>(find.byType(ContentArea)).viewModel;
        editor.titleController.text = 'Synthetic drop destination';
        editor.quillController.document.insert(0, 'Synthetic body');
        expect((await joinWork(tester, editor.saveNote())).isSuccess, isTrue);
        await tester.pump();
        await body(tester, run, editor);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        if (editor != null) {
          await joinWork(tester, editor.closeLibraryResources());
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(() async {
          expect((await app.close()).isSuccess, isTrue);
          await deleteValidationRun(run);
        });
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  scenario(
    'one window drop target attaches from sidebar header dock and bottom edge',
    (tester, run, editor) async {
      final name = editor.currentFileName;
      for (var index = 0; index < 4; index++) {
        // Attachment publication can finish before its row's reveal ends.
        await tester.pumpAndSettle();
        expect(find.byType(DropTarget), findsOneWidget);
        final target = tester.widget<DropTarget>(find.byType(DropTarget));
        expect(target.enable, isTrue);
        final point = switch (index) {
          0 => tester.getCenter(find.byType(Sidebar)),
          1 =>
            tester.getRect(find.byType(ContentArea)).topCenter +
                const Offset(0, 20),
          2 => tester.getCenter(
            find.byKey(const ValueKey('attachment-dock-items')),
          ),
          _ => tester.getCenter(find.byTooltip('Hide notes')),
        };
        expect(tester.getRect(find.byType(DropTarget)).contains(point), isTrue);
        target.onDragEntered!(
          DropEventDetails(localPosition: point, globalPosition: point),
        );
        await tester.pump();
        expect(find.text('Drop files to attach'), findsOneWidget);
        final file = File(p.join(run.path, 'synthetic-$index.txt'))
          ..writeAsStringSync('Synthetic payload $index');
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: point,
            globalPosition: point,
          ),
        );
        await settleWork(
          tester,
          () =>
              editor.attachments.length == index + 1 &&
              !editor.hasAttachmentJobs,
        );
        expect(editor.currentFileName, name);
        expect(editor.attachments.last.fileName, 'synthetic-$index.txt');
      }
      await tester.tap(find.byTooltip('Hide notes'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Sidebar), findsNothing);
      expect(find.byType(DropTarget), findsOneWidget);
      expect(tester.getSize(find.byType(DropTarget)), const Size(1440, 1000));
      expect(
        editor.quillController.document.toPlainText(),
        contains('Synthetic body'),
      );
    },
  );

  scenario('window drop is disabled during busy modal and locked states', (
    tester,
    run,
    editor,
  ) async {
    DropTarget target() => tester.widget<DropTarget>(find.byType(DropTarget));
    final drop = DropDoneDetails(
      files: [DropItemFile(p.join(run.path, 'blocked.txt'))],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );
    editor.setBusy(true);
    await tester.pump();
    expect(target().enable, isFalse);
    target().onDragDone!(drop);
    await tester.pump();
    expect(editor.hasAttachmentJobs, isFalse);
    editor.setBusy(false);
    await tester.pump();
    final context = tester.element(find.byType(ContentArea));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Synthetic modal')),
      ),
    );
    await tester.pumpAndSettle();
    expect(target().enable, isFalse);
    target().onDragDone!(drop);
    await tester.pump();
    expect(editor.hasAttachmentJobs, isFalse);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(target().enable, isTrue);
    expect(
      (await joinWork(
        tester,
        editor.setPassword('synthetic-password'),
      )).isSuccess,
      isTrue,
    );
    expect((await joinWork(tester, editor.manualLock())).isSuccess, isTrue);
    await tester.pump();
    expect(target().enable, isFalse);
    target().onDragDone!(drop);
    await tester.pump();
    expect(editor.attachments, isEmpty);
    expect(editor.hasAttachmentJobs, isFalse);
    expect(
      await joinWork(tester, editor.unlockNote('synthetic-password')),
      isTrue,
    );
    await tester.pump();
    expect(target().enable, isTrue);
  });
}
