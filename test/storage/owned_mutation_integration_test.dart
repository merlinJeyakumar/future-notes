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
    'complete packages import under fresh identities and Delete clears managed generations',
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
        );
        expect(imported.isSuccess, isTrue, reason: imported.message);
        expect(imported.value, isNot(name));
        final reference = (await app.files.resolveNote(imported.value!))!;
        final metadata = await NoteCodec.decode(
          (await app.files.readResolved(reference))!,
          decryptApp: cipher.decryptAppResult,
        );
        expect(
          metadata.note.attachments.every((a) => !ids.contains(a.id)),
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
