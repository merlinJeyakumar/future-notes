import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/note_codec.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import '../support/validation_directory.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';

class PausedEncryption extends EncryptionService {
  Completer<void>? reached;
  Completer<void>? release;
  @override
  Future<String> encryptApp(String text) async {
    final gate = release;
    if (gate != null) {
      release = null;
      reached!.complete();
      await gate.future;
    }
    return super.encryptApp(text);
  }

  (Future<void>, Completer<void>) pause() {
    reached = Completer();
    release = Completer();
    return (reached!.future, release!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late OwnedAppServices app;
  late ContentViewModel editor;
  late PausedEncryption cipher;
  bool editorClosed = false;
  DraftDecisionHandler? decisions;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    app = OwnedAppServices(
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
    );
    expect((await app.initialize()).isSuccess, isTrue);
    cipher = PausedEncryption();
    editorClosed = false;
    decisions = null;
    editor = ContentViewModel(
      fileService: app.files,
      settings: app.settings,
      encryptionService: cipher,
      startBackgroundServices: false,
      onDraftDecision: (request) async =>
          decisions == null ? DraftDecision.discard : await decisions!(request),
    );
  });
  tearDown(() async {
    if (!editorClosed) editor.dispose();
    await editor.closeLibraryResources();
    expect((await app.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });
  Future<File> input([String text = 'synthetic attachment']) async {
    final file = File(p.join(run.path, 'input.txt'));
    await file.writeAsString(text, flush: true);
    return file;
  }

  Future<Map<String, dynamic>> stored() async {
    final ref = await app.files.resolveNote(editor.currentFileName!);
    final decoded = await NoteCodec.decode(
      await app.files.readResolved(ref!) ?? '',
      decryptApp: cipher.decryptAppResult,
    );
    return decoded.metadata;
  }

  Future<void> save() async {
    editor.titleController.text = 'synthetic note';
    editor.quillController.document.insert(0, 'synthetic body');
    final result = await editor.saveNote();
    expect(result.isSuccess, isTrue, reason: result.message);
  }

  test(
    'unlock validates declarations without scanning attachment payloads',
    () async {
      await save();
      await editor.setPassword('synthetic-password');
      final source = await input();
      expect(
        (await editor.addOwnedAttachment(
          source.path,
          'synthetic.txt',
        )).isSuccess,
        isTrue,
      );
      final reference = (await app.files.resolveNote(editor.currentFileName!))!;
      final attachment = editor.attachments.single;
      final phases = <String>[];
      final admitted = await app.files.attachmentSource(
        reference,
        attachment.id,
        verifyContent: false,
        onProgress: (phase, _, _) => phases.add(phase),
      );
      expect(admitted.sha256Hex, isNull);
      expect(admitted.modifiedMicros, isNotNull);
      expect(admitted.length, await File(admitted.path).length());
      expect(phases, isEmpty);
      expect((await editor.manualLock()).isSuccess, isTrue);
      await File(
        p.join(reference.attachmentLocation, '${attachment.id}.med'),
      ).delete();
      await editor.unlockNote('synthetic-password');
      expect(editor.isLocked, isFalse);
      expect(editor.attachments.single.id, attachment.id);
    },
  );

  test(
    'attachment finalization reports journal stage bytes without enabling cancellation',
    () async {
      await save();
      final source = await input('synthetic publication bytes');
      final stages = <String>{};
      var observedBytes = false;
      var becameCancellable = false;
      void watch() {
        for (final job in editor.attachmentJobsNotifier.value) {
          job.progress.addListener(() {
            final state = job.progress.value;
            if (state.phase == AttachmentJobPhase.finalizing &&
                state.detail != null) {
              stages.add(state.detail!);
              observedBytes |= state.bytes > 0;
              becameCancellable |= state.cancellable;
            }
          });
        }
      }

      editor.attachmentJobsNotifier.addListener(watch);
      expect(
        (await editor.addOwnedAttachment(
          source.path,
          'synthetic.txt',
        )).isSuccess,
        isTrue,
      );
      editor.attachmentJobsNotifier.removeListener(watch);
      expect(
        stages,
        containsAll([
          'Writing staged file',
          'Verifying published file',
          'Confirming commit',
        ]),
      );
      expect(observedBytes, isTrue);
      expect(becameCancellable, isFalse);
    },
  );

  test(
    'drop batch uses explicit first Save once and publishes every prepared file',
    () async {
      var prompts = 0;
      decisions = (request) async {
        expect(request.kind, DraftDecisionKind.firstAttachment);
        prompts++;
        return DraftDecision.save;
      };
      final first = await input('first payload');
      final second = File(p.join(run.path, 'second.txt'))
        ..writeAsStringSync('second payload');
      final dropped = editor.attachDroppedFiles([
        first.path,
        second.path,
        first.path,
      ]);
      expect(editor.canAcceptAttachmentDrop, isFalse);
      final result = await dropped;
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(prompts, 1);
      expect(
        editor.attachments.map((a) => a.fileName),
        unorderedEquals(['input.txt', 'second.txt']),
      );
      expect(
        utf8.decode(
          (await editor.readAttachment(
            editor.attachments.firstWhere((a) => a.fileName == 'input.txt').id,
          ))!,
        ),
        'first payload',
      );
      expect((await stored())['attachments'], hasLength(2));
      expect(editor.canAcceptAttachmentDrop, isTrue);
    },
  );

  test(
    'drop rejects invalid batch before Save and first-save cancellation preserves draft',
    () async {
      var prompts = 0;
      decisions = (_) async {
        prompts++;
        return DraftDecision.cancel;
      };
      final first = await input();
      editor.titleController.text = 'Unsaved text';
      expect(
        (await editor.attachDroppedFiles([first.path, run.path])).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(prompts, 0);
      expect(editor.currentFileName, isNull);
      expect(
        (await editor.attachDroppedFiles([first.path])).outcome,
        OperationOutcome.cancelled,
      );
      expect(prompts, 1);
      expect(editor.currentFileName, isNull);
      expect(editor.titleController.text, 'Unsaved text');
      expect(editor.attachments, isEmpty);
      expect(editor.canAcceptAttachmentDrop, isTrue);
    },
  );

  test(
    'UI drop returns after admission and Exit cancels other preparation after a finishing commit',
    () async {
      await save();
      final first = await input();
      final second = File(p.join(run.path, 'queued-large.bin'));
      final sink = await second.open(mode: FileMode.write);
      for (var i = 0; i < 8; i++) {
        await sink.writeFrom(List<int>.filled(1024 * 1024, 42));
      }
      await sink.close();
      final (reached, release) = cipher.pause();
      final committing = editor.addOwnedAttachment(first.path, 'committed.txt');
      await reached.timeout(const Duration(seconds: 15));
      expect(
        (await editor.attachDroppedFiles([
          second.path,
        ], waitForCompletion: false)).isSuccess,
        isTrue,
      );
      expect(editor.canAcceptAttachmentDrop, isTrue);
      expect(editor.hasAttachmentJobs, isTrue);
      var cancellationPrompts = 0;
      decisions = (request) async {
        if (request.kind == DraftDecisionKind.activeAttachments) {
          cancellationPrompts++;
        }
        return DraftDecision.discard;
      };
      final exiting = editor.prepareToExit();
      release.complete();
      expect((await committing).isSuccess, isTrue);
      expect(
        (await exiting.timeout(const Duration(seconds: 15))).isSuccess,
        isTrue,
      );
      expect(cancellationPrompts, 1);
      expect(editor.attachments.single.fileName, 'committed.txt');
      expect(editor.hasAttachmentJobs, isFalse);
    },
  );

  test(
    'drop into unlocked protected note retains encryption and rejects locked note',
    () async {
      await save();
      expect(
        (await editor.setPassword('synthetic-password')).isSuccess,
        isTrue,
      );
      final source = await input();
      expect(
        (await editor.attachDroppedFiles([source.path])).isSuccess,
        isTrue,
      );
      final id = editor.attachments.single.id;
      expect(
        utf8.decode((await editor.readAttachment(id))!),
        'synthetic attachment',
      );
      await editor.manualLock();
      expect(editor.canAcceptAttachmentDrop, isFalse);
      expect(
        (await editor.attachDroppedFiles([source.path])).outcome,
        OperationOutcome.conflict,
      );
      expect(editor.attachments, hasLength(1));
    },
  );

  test(
    'a second drop is admitted during publication and preserves both attachments and typing',
    () async {
      await save();
      final source = await input();
      final (reached, release) = cipher.pause();
      final first = editor.attachDroppedFiles([source.path]);
      await reached.timeout(const Duration(seconds: 15));
      expect(editor.canAcceptAttachmentDrop, isTrue);
      final second = editor.attachDroppedFiles([source.path]);
      editor.quillController.document.insert(0, 'latest typing ');
      release.complete();
      expect((await first).isSuccess, isTrue);
      expect((await second).isSuccess, isTrue);
      expect(editor.attachments, hasLength(2));
      expect((await stored())['attachments'], hasLength(2));
      expect(
        editor.quillController.document.toPlainText(),
        startsWith('latest typing '),
      );
    },
  );

  test(
    'cancelling one admitted file preserves independently queued files',
    () async {
      await save();
      final source = await input();
      final second = File(p.join(run.path, 'later.txt'))
        ..writeAsStringSync('later');
      var cancelled = false;
      void cancelFirst() {
        if (cancelled || editor.attachmentJobsNotifier.value.isEmpty) return;
        cancelled = true;
        unawaited(
          editor.cancelAttachmentJob(
            editor.attachmentJobsNotifier.value.last.progress.value.id,
          ),
        );
      }

      editor.attachmentJobsNotifier.addListener(cancelFirst);
      final result = await editor.attachDroppedFiles([
        source.path,
        second.path,
      ]);
      editor.attachmentJobsNotifier.removeListener(cancelFirst);
      expect(result.outcome, OperationOutcome.cancelled);
      expect(editor.attachments.single.fileName, 'later.txt');
      expect((await stored())['attachments'], hasLength(1));
      expect(editor.canAcceptAttachmentDrop, isTrue);
    },
  );

  test(
    'explicit Save & Continue can persist a blank prerequisite but autosave cannot',
    () async {
      expect(
        (await editor.saveNote(
          isAutoSave: true,
          allowEmptyFirstSave: true,
        )).isSuccess,
        isFalse,
      );
      expect(editor.currentFileName, isNull);
      expect(
        (await editor.saveNote(allowEmptyFirstSave: true)).isSuccess,
        isTrue,
      );
      expect(editor.currentNoteDate, isNotNull);
      final source = await input('');
      expect(
        (await editor.addOwnedAttachment(source.path, 'empty.txt')).isSuccess,
        isTrue,
      );
      expect(
        await editor.readAttachment(editor.attachments.single.id),
        isEmpty,
      );
    },
  );

  test(
    'publication that starts during confirmation cannot be cancelled',
    () async {
      await save();
      final source = await input('synthetic bytes');
      final decision = Completer<DraftDecision>();
      final asked = Completer<void>();
      decisions = (_) {
        if (!asked.isCompleted) asked.complete();
        return decision.future;
      };
      final (reached, release) = cipher.pause();
      final adding = editor.addOwnedAttachment(source.path, 'race.txt');
      final exiting = editor.prepareToExit();
      await asked.future.timeout(const Duration(seconds: 15));
      await reached.timeout(const Duration(seconds: 15));
      final job = editor.attachmentJobsNotifier.value.last;
      expect(job.progress.value.phase, AttachmentJobPhase.finalizing);
      decision.complete(DraftDecision.discard);
      await Future<void>.delayed(Duration.zero);
      await editor.cancelAttachmentJob(job.progress.value.id);
      expect(job.progress.value.phase, AttachmentJobPhase.finalizing);
      release.complete();
      expect((await adding).isSuccess, isTrue);
      expect((await exiting).isSuccess, isTrue);
      expect(editor.attachments.single.fileName, 'race.txt');
      expect(job.progress.value.phase, AttachmentJobPhase.completed);
    },
  );

  test('manual Save uses its own status while typing stays enabled', () async {
    await save();
    editor.titleController.text = 'before commit';
    final (reached, release) = cipher.pause();
    final saving = editor.saveNote();
    await reached.timeout(const Duration(seconds: 15));
    expect(editor.isBusy, isFalse);
    expect(editor.isSavingNotifier.value, isTrue);
    editor.titleController.text = 'typed during Save';
    release.complete();
    expect((await saving).isSuccess, isTrue);
    expect(editor.isSavingNotifier.value, isFalse);
    expect(editor.hasUnsavedChanges, isTrue);
    expect(editor.titleController.text, 'typed during Save');
    expect((await editor.saveNote()).isSuccess, isTrue);
    expect((await stored())['title'], 'typed during Save');
  });

  test(
    'attachment cutover captures typing during preparation and retains commit edits',
    () async {
      await save();
      final source = await input();
      final (reached, release) = cipher.pause();
      final adding = editor.addOwnedAttachment(source.path, 'sample.txt');
      editor.titleController.text = 'typed during preparation';
      await reached.timeout(const Duration(seconds: 15));
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.phase,
        AttachmentJobPhase.finalizing,
      );
      editor.quillController.document.insert(0, 'typed during commit ');
      release.complete();
      expect((await adding).isSuccess, isTrue);
      expect((await stored())['title'], 'typed during preparation');
      expect(editor.hasUnsavedChanges, isTrue);
      expect(
        editor.quillController.document.toPlainText(),
        contains('typed during commit'),
      );
      expect((await editor.saveNote()).isSuccess, isTrue);
      expect((await stored())['content'], contains('typed during commit'));
      expect(
        utf8.decode(
          (await editor.readAttachment(editor.attachments.single.id))!,
        ),
        'synthetic attachment',
      );
    },
  );

  test(
    'password generations keep original objects and preserve body through removal',
    () async {
      await save();
      final source = await input();
      expect(
        (await editor.addOwnedAttachment(source.path, 'same.txt')).isSuccess,
        isTrue,
      );
      final before = await stored();
      final original = editor.attachments.single.id;
      expect((await editor.setPassword('old-password')).isSuccess, isTrue);
      expect(editor.attachments.single.id, isNot(original));
      final firstProtected = editor.attachments.single.id;
      expect(
        (await editor.changePasswordResult('new-password')).isSuccess,
        isTrue,
      );
      expect(editor.attachments.single.id, isNot(firstProtected));
      expect(
        utf8.decode(
          (await editor.readAttachment(editor.attachments.single.id))!,
        ),
        'synthetic attachment',
      );
      expect((await editor.clearPassword()).isSuccess, isTrue);
      expect((await stored())['content'], before['content']);
      final ref = (await app.files.resolveNote(editor.currentFileName!))!;
      expect(
        await File(p.join(ref.attachmentLocation, '$original.med')).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(ref.attachmentLocation, '$firstProtected.med'),
        ).exists(),
        isTrue,
      );
      await editor.manualLock();
      expect(editor.isLocked, isFalse);
    },
  );

  test(
    'missing attachment aborts protection without publishing credentials',
    () async {
      await save();
      final source = await input();
      expect(
        (await editor.addOwnedAttachment(source.path, 'missing.txt')).isSuccess,
        isTrue,
      );
      final before = await stored();
      final ref = (await app.files.resolveNote(editor.currentFileName!))!;
      await File(
        p.join(ref.attachmentLocation, '${editor.attachments.single.id}.med'),
      ).delete();
      final changed = await editor.setPassword('never-published');
      expect(changed.isSuccess, isFalse);
      expect(editor.isPasswordSet, isFalse);
      expect(await stored(), before);
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.phase,
        AttachmentJobPhase.failed,
      );
    },
  );

  test(
    'cancelled preparation closes handles and keeps envelope and attachment list',
    () async {
      await save();
      final before = await stored();
      final source = await input('x' * (2 * 1024 * 1024));
      final adding = editor.addOwnedAttachment(source.path, 'cancel.txt');
      await editor.cancelAttachmentJob(
        editor.attachmentJobsNotifier.value.last.progress.value.id,
      );
      expect((await adding).outcome, OperationOutcome.cancelled);
      expect(await stored(), before);
      expect(editor.attachments, isEmpty);
      await source.delete();
    },
  );

  test(
    'identical packages keep identity and Delete clears managed generations',
    () async {
      await save();
      final source = await input();
      expect(
        (await editor.addOwnedAttachment(
          source.path,
          'duplicate.txt',
        )).isSuccess,
        isTrue,
      );
      expect((await editor.setPassword('note-password')).isSuccess, isTrue);
      final name = editor.currentFileName!;
      final ids = editor.attachments.map((a) => a.id).toSet();
      for (final format in ExportFormat.values) {
        final destination = p.join(run.path, 'export-${format.name}');
        final exported = await editor.exportOwnedPackageTo(
          destination,
          fileName: name,
          format: format,
          password: 'archive-password',
        );
        expect(exported.isSuccess, isTrue, reason: exported.message);
        final imported = await editor.importOwnedFile(
          destination,
          archivePassword: 'archive-password',
          resolveConflict: (_) async => NoteImportDecision.ignore,
        );
        expect(imported.isSuccess, isTrue, reason: imported.message);
        expect(imported.value, name);
        final reference = (await app.files.resolveNote(imported.value!))!;
        final metadata = await NoteCodec.decode(
          (await app.files.readResolved(reference))!,
          decryptApp: cipher.decryptAppResult,
        );
        expect(
          metadata.note.attachments.every((a) => ids.contains(a.id)),
          isTrue,
        );
        expect(editor.currentFileName, name);
      }
      final reviewed = await editor.reviewDeletion(name);
      expect(reviewed, isNotNull);
      expect((await editor.deleteReviewedNote(reviewed!)).isSuccess, isTrue);
      expect(await File(reviewed.contentPath).exists(), isFalse);
      expect(
        await Directory(reviewed.attachmentLocation).list().toList(),
        isEmpty,
      );
      expect(editor.currentFileName, isNull);
    },
  );

  test(
    'export source checking reports bytes and acknowledges cancellation without publishing',
    () async {
      await save();
      final source = await input('x' * (4 * 1024 * 1024));
      expect(
        (await editor.addOwnedAttachment(
          source.path,
          'synthetic.bin',
        )).isSuccess,
        isTrue,
      );
      final before = await stored();
      final destination = File(p.join(run.path, 'cancelled-export.fnote'));
      await destination.writeAsString('previous destination');
      Future<void>? cancellation;
      final watched = <AttachmentJobState>{};
      var sawBytes = false;
      void watch() {
        for (final job in editor.attachmentJobsNotifier.value) {
          if (job.progress.value.operation != AttachmentJobOperation.export ||
              !watched.add(job)) {
            continue;
          }
          job.progress.addListener(() {
            final state = job.progress.value;
            if (state.phase == AttachmentJobPhase.preparing &&
                state.detail?.startsWith('Checking export attachments') ==
                    true &&
                state.bytes > 0 &&
                cancellation == null) {
              sawBytes = true;
              cancellation = editor.cancelAttachmentJob(state.id);
            }
          });
        }
      }

      editor.attachmentJobsNotifier.addListener(watch);
      try {
        final result = await editor
            .exportOwnedPackageTo(destination.path, format: ExportFormat.binary)
            .timeout(const Duration(seconds: 20));
        await cancellation;
        expect(sawBytes, isTrue);
        expect(result.outcome, OperationOutcome.cancelled);
        expect(
          editor.attachmentJobsNotifier.value.last.progress.value.phase,
          AttachmentJobPhase.cancelled,
        );
        expect(await destination.readAsString(), 'previous destination');
        expect(await stored(), before);
        // A second operation can start; cancellation must release the export gate.
        expect(
          (await editor.exportOwnedPackageTo(
            p.join(run.path, 'completed.fnote'),
            format: ExportFormat.binary,
          )).isSuccess,
          isTrue,
        );
      } finally {
        editor.attachmentJobsNotifier.removeListener(watch);
      }
    },
  );

  test(
    'exports cannot replace note payloads or application settings',
    () async {
      await save();
      final ref = (await app.files.resolveNote(editor.currentFileName!))!;
      final before = await File(ref.contentPath).readAsBytes();
      final result = await editor.exportOwnedPackageTo(
        ref.contentPath,
        format: ExportFormat.binary,
      );
      expect(result.isSuccess, isFalse);
      expect(await File(ref.contentPath).readAsBytes(), before);
      final settings = await app.settings.getSettingsFilePath();
      final blocked = await editor.exportOwnedPackageTo(
        settings,
        format: ExportFormat.binary,
      );
      expect(blocked.isSuccess, isFalse);
    },
  );

  test(
    'legacy aliases cannot delete a shared attachment owner or its folder note',
    () async {
      await save();
      final source = await input();
      expect(
        (await editor.addOwnedAttachment(source.path, 'shared.txt')).isSuccess,
        isTrue,
      );
      final originalName = editor.currentFileName!;
      final ref = (await app.files.resolveNote(originalName))!;
      final alias = File(ref.binding.child('legacy-alias.enc'));
      await alias.writeAsString(jsonEncode(await stored()), flush: true);
      for (final name in [originalName, 'legacy-alias.enc']) {
        final reviewed = (await editor.reviewDeletion(name))!;
        final result = await editor.deleteReviewedNote(reviewed);
        expect(result.outcome, OperationOutcome.conflict);
        expect(await File(ref.contentPath).exists(), isTrue);
        expect(await alias.exists(), isTrue);
        expect(
          await File(
            p.join(
              ref.attachmentLocation,
              '${editor.attachments.single.id}.med',
            ),
          ).exists(),
          isTrue,
        );
        expect(editor.quillController.readOnly, isFalse);
        expect(editor.isDeletingCurrent, isFalse);
      }
    },
  );

  test(
    'attachment removal commits metadata but keeps recovery payload',
    () async {
      await save();
      final source = await input();
      expect(
        (await editor.addOwnedAttachment(source.path, 'kept.txt')).isSuccess,
        isTrue,
      );
      final id = editor.attachments.single.id;
      final ref = (await app.files.resolveNote(editor.currentFileName!))!;
      await editor.removeAttachment(id);
      expect(editor.attachments, isEmpty);
      expect((await stored())['attachments'], isEmpty);
      expect(
        await File(p.join(ref.attachmentLocation, '$id.med')).exists(),
        isTrue,
      );
    },
  );

  test(
    'native library switch admits a selected root and persists setting before publication',
    () async {
      // Real native capability admission exercised with synthetic locations only.
      editor.dispose();
      editorClosed = true;
      await editor.closeLibraryResources();
      expect((await app.close()).isSuccess, isTrue);
      final root = p.join(run.path, 'native-original');
      final selectedSettings = File(
        p.join(run.path, 'native-settings', 'settings.json'),
      );
      await selectedSettings.parent.create(recursive: true);
      await selectedSettings.writeAsString(
        jsonEncode({'customDataPath': root}),
        flush: true,
      );
      app = OwnedAppServices(
        environment: StorageEnvironment.recoverable(
          dataRoot: root,
          settingsFile: p.join(run.path, 'native-settings', 'settings.json'),
        ),
      );
      expect((await app.initialize()).isSuccess, isTrue);
      editor = ContentViewModel(
        fileService: app.files,
        settings: app.settings,
        encryptionService: cipher,
        startBackgroundServices: false,
      );
      editorClosed = false;
      final next = p.join(run.path, 'native-selected');
      final switched = await editor.switchLibrary(next);
      expect(switched.isSuccess, isTrue, reason: switched.message);
      expect(await app.settings.getUserDataPath(), next);
      await save();
      final reference = (await app.files.resolveNote(editor.currentFileName!))!;
      expect(p.isWithin(next, reference.contentPath), isTrue);
      expect(
        await Directory(
          root,
        ).list().where((f) => p.basename(f.path).startsWith('note_')).toList(),
        isEmpty,
      );
    },
  );
}
