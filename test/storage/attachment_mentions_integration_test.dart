import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/routing/fnotes_uri.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late OwnedAppServices app;
  late ContentViewModel editor;
  late AttachmentOpenCache cache;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    app = OwnedAppServices(
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: p.join(run.path, 'configuration/settings.json'),
      ),
    );
    expect((await app.initialize()).isSuccess, isTrue);
    await Directory(p.join(run.path, 'cache')).create();
    cache = AttachmentOpenCache(
      rootResolver: () async => p.join(run.path, 'cache'),
      sourceResolver: app.files.attachmentSource,
    );
    editor = ContentViewModel(
      fileService: app.files,
      encryptionService: EncryptionService(),
      settings: app.settings,
      attachmentOpenCache: cache,
      startBackgroundServices: false,
      onDraftDecision: (_) async => DraftDecision.discard,
    );
  });
  tearDown(() async {
    await editor.closeAttachmentCache();
    editor.dispose();
    await editor.closeLibraryResources();
    expect((await app.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });

  Future<String> createMention() async {
    editor.titleController.text = 'Synthetic mention';
    expect((await editor.saveNote()).isSuccess, isTrue);
    final file = File(p.join(run.path, 'source.txt'));
    await file.writeAsString('synthetic attachment contents');
    expect(
      (await editor.addOwnedAttachment(
        file.path,
        'report final.txt',
      )).isSuccess,
      isTrue,
    );
    final id = editor.attachments.single.id;
    editor.quillController.replaceText(
      0,
      0,
      '@rep',
      const TextSelection.collapsed(offset: 4),
    );
    expect(
      editor
          .insertAttachmentMention(
            attachmentId: id,
            query: editor.attachmentMentionQuery()!,
            owner: editor.draftSession.generation,
            mode: editor.editorMode,
          )
          .isSuccess,
      isTrue,
    );
    expect((await editor.saveNote()).isSuccess, isTrue);
    return id;
  }

  test(
    'rekey preserves reference, repeated opening reuses cache until lock; removal is unavailable',
    () async {
      final stable = await createMention();
      final url = FnotesTarget.attachment(stable);
      final first = await editor.openAttachment(
        editor.resolveInternalLink(url).value!,
      );
      expect(first.isSuccess, isTrue, reason: first.message);
      final transforms = cache.transformCount;
      expect(
        (await editor.openAttachment(
          editor.resolveInternalLink(url).value!,
        )).value!.path,
        first.value!.path,
      );
      expect(cache.transformCount, transforms);
      final savedName = editor.currentFileName!;
      await editor.reset();
      await editor.loadNote(savedName);
      expect(
        (await editor.openAttachment(
          editor.resolveInternalLink(url).value!,
        )).value!.path,
        first.value!.path,
      );
      expect(cache.transformCount, transforms);
      expect(
        (await editor.setPassword('synthetic-password')).isSuccess,
        isTrue,
      );
      expect(editor.attachments.single.id, isNot(stable));
      expect(editor.attachments.single.mentionId, stable);
      expect(editor.resolveInternalLink(url).isSuccess, isTrue);
      expect((await editor.manualLock()).isSuccess, isTrue);
      expect(editor.resolveInternalLink(url).isSuccess, isFalse);
      expect(await editor.unlockNote('synthetic-password'), isTrue);
      final reopened = await editor.openAttachment(
        editor.resolveInternalLink(url).value!,
      );
      expect(reopened.isSuccess, isTrue, reason: reopened.message);
      expect(
        await File(reopened.value!.path).readAsString(),
        'synthetic attachment contents',
      );
      expect(await editor.removePassword(), isTrue);
      expect(editor.attachments.single.mentionId, stable);
      expect(
        (await editor.removeAttachment(editor.attachments.single.id)).isSuccess,
        isTrue,
      );
      expect(editor.resolveInternalLink(url).isSuccess, isFalse);
    },
  );

  for (final format in ExportFormat.values) {
    test(
      '${format.name} locked export/import, duplicate and replace preserve links across storage IDs',
      () async {
        final stable = await createMention();
        expect(
          (await editor.setPassword('synthetic-password')).isSuccess,
          isTrue,
        );
        final oldStorage = editor.attachments.single.id;
        final destination = p.join(run.path, 'export.${format.name}');
        expect(
          (await editor.exportOwnedPackageTo(
            destination,
            format: format,
          )).isSuccess,
          isTrue,
        );
        final result = await editor.importNoteFile(
          destination,
          resolveConflict: (match) async {
            expect(match.identical, isTrue);
            return NoteImportDecision.duplicate;
          },
        );
        expect(result.isSuccess, isTrue, reason: result.message);
        expect(result.value!.disposition, NoteImportDisposition.duplicated);
        await editor.loadNote(result.value!.fileName);
        expect(editor.isLocked, isTrue);
        expect(editor.attachments.single.id, isNot(oldStorage));
        expect(editor.attachments.single.mentionId, stable);
        expect(await editor.unlockNote('synthetic-password'), isTrue);
        final url = FnotesTarget.attachment(stable);
        final resolved = editor.resolveInternalLink(url);
        expect(resolved.isSuccess, isTrue);
        expect(
          editor.quillController.document
              .toDelta()
              .toJson()
              .first['attributes'],
          containsPair('link', url),
        );
        final opened = await editor.openAttachment(resolved.value!);
        expect(opened.isSuccess, isTrue, reason: opened.message);
        expect(
          await File(opened.value!.path).readAsString(),
          'synthetic attachment contents',
        );
        final duplicateExport = p.join(run.path, 'duplicate.${format.name}');
        expect(
          (await editor.exportOwnedPackageTo(
            duplicateExport,
            format: format,
          )).isSuccess,
          isTrue,
        );
        var prompted = false;
        final ignored = await editor.importNoteFile(
          duplicateExport,
          resolveConflict: (match) async {
            prompted = true;
            expect(match.identical, isTrue);
            return NoteImportDecision.ignore;
          },
        );
        expect(ignored.isSuccess, isTrue);
        expect(prompted, isTrue);
        final replaced = await editor.importNoteFile(
          duplicateExport,
          resolveConflict: (_) async => NoteImportDecision.replace,
        );
        expect(replaced.isSuccess, isTrue, reason: replaced.message);
        expect(replaced.value!.disposition, NoteImportDisposition.replaced);
        await editor.loadNote(replaced.value!.fileName);
        if (editor.isLocked) {
          expect(await editor.unlockNote('synthetic-password'), isTrue);
        }
        expect(editor.resolveInternalLink(url).isSuccess, isTrue);
      },
    );
  }
}
