import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/commit_record.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/models/save_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/note_codec.dart';
import 'package:flutter_application_1/features/dashboard/services/note_import_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late OwnedAppServices app;
  late ContentViewModel editor;
  late EncryptionService cipher;
  var serial = 0;
  DraftDecision decision = DraftDecision.cancel;
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
    cipher = EncryptionService();
    decision = DraftDecision.cancel;
    editor = ContentViewModel(
      fileService: app.files,
      settings: app.settings,
      encryptionService: cipher,
      startBackgroundServices: false,
      onDraftDecision: (_) async => decision,
    );
  });
  tearDown(() async {
    editor.dispose();
    await editor.closeLibraryResources();
    expect((await app.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });

  Map<String, dynamic> note({
    String id = 'persistent-legacy-id',
    String title = 'Original',
  }) => {
    'id': id,
    'title': title,
    'content': '  synthetic body\n',
    'isLocked': false,
    'timestamp': 1700000000000,
    'attachments': [],
    'unknown': {'b': 2, 'a': 1},
  };

  Future<NoteReference> seed(
    Map<String, dynamic> metadata, {
    bool legacy = false,
  }) async {
    final storageId = 'synthetic-${serial++}';
    final ref = legacy ? null : await app.files.newNoteReference(storageId);
    final file = File(
      legacy
          ? p.join(app.environment.dataRoot!, '$storageId.enc')
          : ref!.contentPath,
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      legacy
          ? jsonEncode(metadata)
          : await cipher.encryptApp(jsonEncode(metadata)),
      flush: true,
    );
    return (await app.files.resolveNote(
      legacy ? '$storageId.enc' : ref!.fileName,
    ))!.withModelId(metadata['id'] as String);
  }

  Future<String> package(
    Map<String, dynamic> metadata, {
    ExportFormat format = ExportFormat.binary,
    Map<String, StreamingFileSource> attachments = const {},
    String? password,
  }) async {
    final operation = await Directory(
      p.join(run.path, 'pack-${serial++}'),
    ).create();
    final destination = p.join(
      run.path,
      'import-${serial++}.${format == ExportFormat.zip ? 'zip' : 'fnote'}',
    );
    await StreamingPackService().exportPackage(
      metadata: metadata,
      attachments: attachments,
      format: format,
      destination: destination,
      operationDirectory: operation.path,
      password: password,
    );
    return destination;
  }

  Future<Map<String, dynamic>> stored(String name) async {
    final ref = (await app.files.resolveNote(name))!;
    return (await NoteCodec.decode(
      (await app.files.readResolved(ref))!,
      decryptApp: cipher.decryptAppResult,
    )).metadata;
  }

  Future<List<String>> notes() async => (await app.files.getRecentFiles())
      .where((name) => name.startsWith('note_') || name.endsWith('.enc'))
      .toList();

  Future<StreamingFileSource> payload(String name) async {
    final bytes = await cipher.encryptBinary(
      Uint8List.fromList(utf8.encode('synthetic $name')),
    );
    final file = File(p.join(run.path, '$name.med'));
    await file.writeAsBytes(bytes, flush: true);
    return StreamingFileSource(file.path, bytes.length);
  }

  for (final format in ExportFormat.values) {
    test(
      '${format.name} retains UID and prompts even for identical content after attachment remapping',
      () async {
        final metadata = note(id: '../opaque-uid:kept');
        metadata['attachments'] = [
          {
            'id': 'source',
            'fileName': 'synthetic.txt',
            'size': 19,
            'unknownAttachment': {'value': true},
          },
        ];
        final source = await package(
          metadata,
          format: format,
          attachments: {'source': await payload('input')},
        );
        final first = await editor.importNoteFile(source);
        expect(first.isSuccess, isTrue, reason: first.message);
        expect(first.value!.disposition, NoteImportDisposition.created);
        final saved = await stored(first.value!.fileName);
        expect(saved['id'], metadata['id']);
        expect(saved['unknown'], metadata['unknown']);
        expect(saved['content'], metadata['content']);
        expect(saved['timestamp'], metadata['timestamp']);
        expect((saved['attachments'] as List).single['id'], isNot('source'));
        var prompts = 0;
        final second = await editor.importNoteFile(
          source,
          resolveConflict: (match) async {
            prompts++;
            expect(match.identical, isTrue);
            return NoteImportDecision.ignore;
          },
        );
        expect(second.isSuccess, isTrue, reason: second.message);
        expect(second.value!.disposition, NoteImportDisposition.ignored);
        expect(second.value!.fileName, first.value!.fileName);
        expect(prompts, 1);
        expect(await notes(), hasLength(1));
        expect(
          (await editor.loadNote(first.value!.fileName)).isSuccess,
          isTrue,
        );
        editor.titleController.text = 'Edited';
        expect((await editor.saveNote()).isSuccess, isTrue);
        expect((await stored(first.value!.fileName))['id'], metadata['id']);
        final exported = p.join(run.path, 'roundtrip.${format.name}');
        expect(
          (await editor.exportOwnedPackageTo(
            exported,
            format: format,
          )).isSuccess,
          isTrue,
        );
        final directory = await Directory(p.join(run.path, 'inspect')).create();
        final roundtrip = await StreamingPackService().importPackage(
          source: exported,
          operationDirectory: directory.path,
        );
        expect(roundtrip.note.note.id, metadata['id']);
      },
    );
  }

  test(
    'matching UID in a locked hidden note skips without a password',
    () async {
      final metadata = note();
      metadata['isLocked'] = true;
      metadata['content'] = await cipher.encrypt(
        'synthetic locked\n',
        password: 'synthetic-password',
      );
      final ref = await seed(metadata);
      editor.setSearchQuery('does not match');
      final result = await editor.importNoteFile(
        await package(metadata, password: 'archive'),
        archivePassword: 'archive',
        resolveConflict: (_) async => NoteImportDecision.ignore,
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.value!.disposition, NoteImportDisposition.ignored);
      expect(result.value!.fileName, ref.fileName);
      expect(await notes(), hasLength(1));
    },
  );

  test(
    'confirmed replacement retains previous envelope, attachment and unknown fields',
    () async {
      final before = note();
      before['attachments'] = [
        {'id': 'old', 'fileName': 'old.txt', 'size': 3},
      ];
      final ref = await seed(before);
      final oldPayload = await payload('old');
      final oldFile = File(p.join(ref.attachmentLocation, 'old.med'));
      await oldFile.parent.create(recursive: true);
      await File(oldPayload.path).copy(oldFile.path);
      final oldEnvelope = await File(ref.contentPath).readAsString();
      expect((await editor.loadNote(ref.fileName)).isSuccess, isTrue);
      final next = note(title: 'Imported revision');
      next['attachments'] = [
        {'id': 'new', 'fileName': 'new.txt', 'size': 3},
      ];
      final result = await editor.importNoteFile(
        await package(next, attachments: {'new': await payload('new')}),
        resolveConflict: (conflict) async {
          expect(conflict.reference.contentPath, ref.contentPath);
          expect(conflict.reference.storageRevision, isNotNull);
          expect(conflict.title, 'Original');
          return NoteImportDecision.replace;
        },
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.value!.disposition, NoteImportDisposition.replaced);
      expect(result.value!.fileName, ref.fileName);
      expect(await notes(), hasLength(1));
      expect(editor.titleController.text, 'Imported revision');
      expect(editor.hasUnsavedChanges, isFalse);
      expect((await stored(ref.fileName))['unknown'], before['unknown']);
      expect(
        await oldFile.readAsBytes(),
        await File(oldPayload.path).readAsBytes(),
      );
      final recoveries = await Directory(
        p.join(ref.binding.root, '.future-notes-storage', 'recovery'),
      ).list(recursive: true).toList();
      final previous = recoveries.whereType<File>().where(
        (file) => file.path.endsWith('.previous'),
      );
      expect(previous, isNotEmpty);
      expect(
        await Future.wait(previous.map((file) => file.readAsString())),
        contains(oldEnvelope),
      );
      expect(
        (await editor.importNoteFile(
          await package(next, attachments: {'new': await payload('same-new')}),
          resolveConflict: (_) async => NoteImportDecision.ignore,
        )).value!.disposition,
        NoteImportDisposition.ignored,
      );
    },
  );

  test('Ignore retains envelope, draft and note count', () async {
    final ref = await seed(note());
    await editor.loadNote(ref.fileName);
    final before = await File(ref.contentPath).readAsBytes();
    final result = await editor.importNoteFile(
      await package(note(title: 'Different')),
      resolveConflict: (_) async => NoteImportDecision.ignore,
    );
    expect(result.value!.disposition, NoteImportDisposition.ignored);
    expect(await File(ref.contentPath).readAsBytes(), before);
    expect(editor.titleController.text, 'Original');
    expect(await notes(), hasLength(1));
  });

  test(
    'replacement requires explicit confirmation even for non-UI callers',
    () async {
      final ref = await seed(note());
      final result = await editor.importNoteFile(
        await package(note(title: 'Different')),
      );
      expect(result.outcome, OperationOutcome.conflict);
      expect((await stored(ref.fileName))['title'], 'Original');
    },
  );

  test('dirty first draft Cancel aborts before import publication', () async {
    editor.titleController.text = 'Unsaved synthetic draft';
    final result = await editor.importNoteFile(await package(note()));
    expect(result.outcome, OperationOutcome.cancelled);
    expect(editor.titleController.text, 'Unsaved synthetic draft');
    expect(await notes(), isEmpty);
  });

  test(
    'edits during confirmation are retained and block replacement',
    () async {
      final ref = await seed(note());
      await editor.loadNote(ref.fileName);
      final before = await File(ref.contentPath).readAsBytes();
      final result = await editor.importNoteFile(
        await package(note(title: 'Incoming')),
        resolveConflict: (_) async {
          editor.titleController.text = 'Typed during confirmation';
          return NoteImportDecision.replace;
        },
      );
      expect(result.outcome, OperationOutcome.conflict);
      expect(editor.titleController.text, 'Typed during confirmation');
      expect(editor.hasUnsavedChanges, isTrue);
      expect(await File(ref.contentPath).readAsBytes(), before);
    },
  );

  test(
    'external revision change during confirmation cannot be overwritten',
    () async {
      final ref = await seed(note());
      final external = await cipher.encryptApp(
        jsonEncode(note(title: 'External revision')),
      );
      final result = await editor.importNoteFile(
        await package(note(title: 'Incoming')),
        resolveConflict: (_) async {
          await File(ref.contentPath).writeAsString(external, flush: true);
          return NoteImportDecision.replace;
        },
      );
      expect(result.outcome, OperationOutcome.conflict);
      expect(await File(ref.contentPath).readAsString(), external);
    },
  );

  test('backup failure preserves existing note and editor', () async {
    final ref = await seed(note());
    await editor.loadNote(ref.fileName);
    final before = await File(ref.contentPath).readAsBytes();
    final target = p.posix.joinAll(
      p.split(p.relative(ref.contentPath, from: ref.binding.root)),
    );
    final result = await editor.importNoteFile(
      await package(note(title: 'Incoming')),
      resolveConflict: (_) async {
        final baseline = Directory(
          p.join(
            ref.binding.root,
            '.future-notes-storage',
            'recovery',
            CommitRecord.objectIdentity(target),
            'baseline',
          ),
        );
        await baseline.create(
          recursive: true,
        ); // A directory cannot be a verified backup file.
        return NoteImportDecision.replace;
      },
    );
    expect(result.isSuccess, isFalse);
    expect(await File(ref.contentPath).readAsBytes(), before);
    expect(editor.titleController.text, 'Original');
    expect(editor.isImportCutover, isFalse);
    expect(await notes(), hasLength(1));
  });

  test(
    'ambiguous existing IDs stop without selecting or modifying a note',
    () async {
      final first = await seed(note());
      final second = await seed(note(title: 'Another existing copy'));
      final a = await File(first.contentPath).readAsBytes();
      final b = await File(second.contentPath).readAsBytes();
      var prompts = 0;
      final result = await editor.importNoteFile(
        await package(note(title: 'Incoming')),
        resolveConflict: (_) async {
          prompts++;
          return NoteImportDecision.replace;
        },
      );
      expect(result.outcome, OperationOutcome.rejectedInput);
      expect(result.message, contains('Multiple notes'));
      expect(prompts, 0);
      expect(await File(first.contentPath).readAsBytes(), a);
      expect(await File(second.contentPath).readAsBytes(), b);
    },
  );

  test('legacy JSON replacement preserves format and persistent ID', () async {
    final ref = await seed(note(), legacy: true);
    final next = note(title: 'Legacy replacement');
    final result = await editor.importNoteFile(
      await package(next),
      resolveConflict: (_) async => NoteImportDecision.replace,
    );
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(jsonDecode(await File(ref.contentPath).readAsString()), next);
    expect(result.value!.fileName, ref.fileName);
  });

  test(
    'loose encrypted imports retain ID and plain text imports remain separate',
    () async {
      final encrypted = File(p.join(run.path, 'loose.enc'));
      await encrypted.writeAsString(
        await cipher.encryptApp(jsonEncode(note())),
      );
      final first = await editor.importNoteFile(encrypted.path);
      expect(first.isSuccess, isTrue, reason: first.message);
      final second = await editor.importNoteFile(
        encrypted.path,
        resolveConflict: (_) async => NoteImportDecision.ignore,
      );
      expect(second.value!.disposition, NoteImportDisposition.ignored);
      expect((await stored(first.value!.fileName))['id'], note()['id']);
      final text = File(p.join(run.path, 'plain.txt'));
      await text.writeAsString('synthetic text');
      final a = await editor.importNoteFile(text.path, plainText: true);
      final b = await editor.importNoteFile(text.path, plainText: true);
      expect(a.isSuccess && b.isSuccess, isTrue);
      expect(
        (await stored(a.value!.fileName))['id'],
        isNot((await stored(b.value!.fileName))['id']),
      );
      expect(await text.readAsString(), 'synthetic text');
    },
  );

  test(
    'binary exports alongside notes do not prevent duplicate detection',
    () async {
      final ref = await seed(note());
      final source = await package(note(), format: ExportFormat.zip);
      await File(source).copy(p.join(ref.binding.root, 'backup.zip'));
      final result = await editor.importNoteFile(
        source,
        resolveConflict: (_) async => NoteImportDecision.ignore,
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.value!.disposition, NoteImportDisposition.ignored);
      expect(await notes(), hasLength(1));
    },
  );

  test(
    'late draft edits are retained after publication with an accurate partial outcome',
    () async {
      final ref = await seed(note());
      await editor.loadNote(ref.fileName);
      Future<OperationResult<void>>? blockedSave;
      Future<OperationResult<void>>? blockedMode;
      void onCutover() {
        if (!editor.isImportCutover) return;
        editor.removeListener(onCutover);
        expect(editor.quillController.readOnly, isTrue);
        blockedSave = editor.saveNote();
        blockedMode = editor.setEditorMode(EditorMode.html);
        scheduleMicrotask(
          () => editor.titleController.text = 'Late synthetic edit',
        );
      }

      editor.addListener(onCutover);
      final result = await editor.importNoteFile(
        await package(note(title: 'Committed import')),
        resolveConflict: (_) async => NoteImportDecision.replace,
      );
      expect(result.outcome, OperationOutcome.recoveryRequired);
      expect(result.value!.disposition, NoteImportDisposition.replaced);
      expect((await blockedSave!).outcome, OperationOutcome.conflict);
      expect((await blockedMode!).isSuccess, isFalse);
      expect((await stored(ref.fileName))['title'], 'Committed import');
      expect(editor.titleController.text, 'Late synthetic edit');
      expect(editor.hasUnsavedChanges, isTrue);
      expect(editor.draftSession.canWrite, isFalse);
      expect(editor.quillController.readOnly, isTrue);
    },
  );

  test(
    'replacement clears old credentials and requires unlocking the imported protection',
    () async {
      final before = note();
      before['isLocked'] = true;
      before['content'] = await cipher.encrypt(
        'original protected\n',
        password: 'old',
      );
      final ref = await seed(before);
      await editor.loadNote(ref.fileName);
      expect(await editor.unlockNote('old'), isTrue);
      final next = note(title: 'New protection');
      next['isLocked'] = true;
      next['content'] = await cipher.encrypt(
        'imported protected\n',
        password: 'new',
      );
      final result = await editor.importNoteFile(
        await package(next),
        resolveConflict: (_) async => NoteImportDecision.replace,
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(editor.isLocked, isTrue);
      expect(await editor.unlockNote('old'), isFalse);
      expect(await editor.unlockNote('new'), isTrue);
      expect(
        editor.quillController.document.toPlainText(),
        contains('imported protected'),
      );
    },
  );

  test(
    'cancellation during replacement confirmation performs no publication',
    () async {
      final ref = await seed(note());
      final before = await File(ref.contentPath).readAsBytes();
      final result = await editor.importNoteFile(
        await package(note(title: 'Cancelled import')),
        resolveConflict: (_) async {
          await editor.cancelAttachmentJob(
            editor.attachmentJobsNotifier.value.last.progress.value.id,
          );
          return NoteImportDecision.replace;
        },
      );
      expect(result.outcome, OperationOutcome.cancelled);
      expect(await File(ref.contentPath).readAsBytes(), before);
      expect(await notes(), hasLength(1));
    },
  );

  for (final identical in [false, true]) {
    for (final choice in NoteImportDecision.values) {
      test(
        'same UID identical=$identical prompts and applies ${choice.name}',
        () async {
          final before = note();
          final ref = await seed(before);
          final original = await File(ref.contentPath).readAsBytes();
          final incoming = identical
              ? note()
              : note(title: 'Incoming revision');
          var prompts = 0;
          final result = await editor.importNoteFile(
            await package(incoming),
            resolveConflict: (match) async {
              prompts++;
              expect(match.identical, identical);
              expect(match.reference.contentPath, ref.contentPath);
              return choice;
            },
          );
          expect(result.isSuccess, isTrue, reason: result.message);
          expect(prompts, 1);
          if (choice == NoteImportDecision.duplicate) {
            expect(result.value!.disposition, NoteImportDisposition.duplicated);
            expect(result.value!.fileName, isNot(ref.fileName));
            expect(await notes(), hasLength(2));
            expect(await File(ref.contentPath).readAsBytes(), original);
            final copy = await stored(result.value!.fileName);
            expect(copy['id'], isNot(before['id']));
            expect(copy['title'], incoming['title']);
            expect(copy['content'], incoming['content']);
            expect(copy['unknown'], incoming['unknown']);
            var reimportPrompts = 0;
            await editor.loadNote(result.value!.fileName);
            final exported = p.join(run.path, 'duplicate-roundtrip.fnote');
            expect(
              (await editor.exportOwnedPackageTo(
                exported,
                format: ExportFormat.binary,
              )).isSuccess,
              isTrue,
            );
            final repeated = await editor.importNoteFile(
              exported,
              resolveConflict: (match) async {
                reimportPrompts++;
                expect(match.reference.fileName, result.value!.fileName);
                expect(match.identical, isTrue);
                return NoteImportDecision.ignore;
              },
            );
            expect(repeated.value!.disposition, NoteImportDisposition.ignored);
            expect(reimportPrompts, 1);
            expect(await notes(), hasLength(2));
          } else if (choice == NoteImportDecision.replace) {
            expect(result.value!.disposition, NoteImportDisposition.replaced);
            expect(result.value!.fileName, ref.fileName);
            expect(await notes(), hasLength(1));
            expect(await stored(ref.fileName), incoming);
            final copies =
                await Directory(
                      p.join(
                        ref.binding.root,
                        '.future-notes-storage',
                        'recovery',
                      ),
                    )
                    .list(recursive: true)
                    .where(
                      (file) => file is File && file.path.endsWith('.previous'),
                    )
                    .toList();
            expect(copies, isNotEmpty);
            expect(
              await Future.wait(
                copies.map((file) => File(file.path).readAsBytes()),
              ),
              anyElement(orderedEquals(original)),
            );
          } else {
            expect(result.value!.disposition, NoteImportDisposition.ignored);
            expect(await notes(), hasLength(1));
            expect(await File(ref.contentPath).readAsBytes(), original);
          }
        },
      );
    }
  }

  test(
    'fingerprints ignore key order and attachment IDs but retain unknown fields',
    () async {
      final source = await payload('compare');
      final a = note();
      a['attachments'] = [
        {
          'id': 'first',
          'fileName': 'same.txt',
          '_payloadSha256': 'unknown metadata',
        },
      ];
      final b = <String, dynamic>{
        for (final key in a.keys.toList().reversed) key: a[key],
      };
      b['unknown'] = {'a': 1, 'b': 2};
      b['attachments'] = [
        {
          'id': 'other',
          'fileName': 'same.txt',
          '_payloadSha256': 'unknown metadata',
        },
      ];
      final expected = await NoteImportService.fingerprint(a, {
        'first': source,
      });
      expect(
        await NoteImportService.fingerprint(b, {'other': source}),
        expected,
      );
      b['content'] = 'synthetic body\n';
      expect(
        await NoteImportService.fingerprint(b, {'other': source}),
        isNot(expected),
      );
      b['content'] = a['content'];
      (b['attachments'] as List).single['_payloadSha256'] = 'changed';
      expect(
        await NoteImportService.fingerprint(b, {'other': source}),
        isNot(expected),
      );
    },
  );
}
