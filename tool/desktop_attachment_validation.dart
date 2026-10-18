import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../lib/core/platform/windows_desktop_actions.dart';
import '../lib/core/storage/attachment_open_cache.dart';
import '../lib/core/storage/attachment_transform_worker.dart';
import '../lib/core/storage/attachment_performance.dart';
import '../lib/core/storage/note_reference.dart';
import '../lib/core/storage/owned_write.dart';
import '../lib/core/storage/owned_app_services.dart';
import '../lib/core/storage/storage_environment.dart';
import '../lib/core/storage/streaming_file_cipher.dart';
import '../lib/features/dashboard/models/note_model.dart';
import '../lib/features/dashboard/services/encryption_service.dart';
import '../lib/features/dashboard/viewmodels/content_viewmodel.dart';
import '../lib/features/dashboard/services/streaming_pack_service.dart';
import '../lib/features/dashboard/services/pack_service.dart';
import '../lib/features/dashboard/services/note_codec.dart';
import '../lib/features/dashboard/models/note_import.dart';

// Standalone synthetic release probe. Never loads settings or a user library.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Synthetic attachment validation')),
      ),
    ),
  );
  final run = await Directory.systemTemp.createTemp('future-notes-validation-');
  final root = await WindowsDesktopActions().cacheRoot(
    validationRoot: run.path,
  );
  final rows = <Map<String, Object?>>[];
  for (final size in [15, 448706, 1048593]) {
    for (final password in <String?>[null, 'synthetic-password']) {
      final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
      final encrypted = await EncryptionService(
        useNative: false,
      ).encryptBinary(bytes, password: password);
      final sourceFile = File(p.join(run.path, 'source-${rows.length}.med'));
      await sourceFile.writeAsBytes(encrypted, flush: true);
      final source = StreamingFileSource(sourceFile.path, encrypted.length);
      final row = <String, Object?>{
        'size': size,
        'protected': password != null,
      };
      final direct = p.join(root, 'direct-${rows.length}');
      try {
        await StreamingFileCipher.transform(
          source: source,
          destination: direct,
          decryptSource: true,
          encryptDestination: false,
          sourcePassword: password,
          verifyOutput: false,
          ownedTarget: OwnedWriteTarget.forPath(direct),
          expectedPlaintextBytes: size,
        );
        row['direct'] = _equal(await File(direct).readAsBytes(), bytes);
      } catch (e) {
        row['direct'] = false;
        row['errorType'] = e.runtimeType.toString();
        if (e is FormatException) row['reason'] = e.message;
        if (e is FileSystemException) row['osCode'] = e.osError?.errorCode;
      }
      final worker = AttachmentTransformWorker();
      final workerPath = p.join(root, 'worker-${rows.length}');
      final transformed = await worker
          .submit(
            FileTransformRequest(
              source: source,
              destination: workerPath,
              decryptSource: true,
              encryptDestination: false,
              sourcePassword: password,
              verifyOutput: false,
              ownedTarget: OwnedWriteTarget.forPath(workerPath),
              expectedPlaintextBytes: size,
            ),
          )
          .result;
      row['worker'] = transformed.isSuccess;
      row['workerMessage'] = transformed.message;
      await worker.close();
      final cache = AttachmentOpenCache(
        rootResolver: () async => root,
        sourceResolver: (_, _) async => source,
      );
      final binding = StorageBinding(run.path, 0);
      final note = NoteReference(
        binding: binding,
        fileName: 'synthetic',
        format: NoteStorageFormat.folder,
        contentPath: binding.child('synthetic/content.enc'),
        attachmentLocation: binding.child('synthetic/attachments'),
      );
      final attachment = AttachmentModel(
        id: 'synthetic',
        fileName: 'synthetic.bin',
        size: size,
      );
      final opened = await cache.prepare(
        note,
        attachment,
        0,
        password: password,
      );
      row['cache'] =
          opened.isSuccess &&
          _equal(await File(opened.value!.path).readAsBytes(), bytes);
      row['cacheMessage'] = opened.message;
      final again = await cache.prepare(
        note,
        attachment,
        0,
        password: password,
      );
      row['reused'] =
          again.isSuccess &&
          opened.value?.path == again.value?.path &&
          cache.transformCount == 1;
      await cache.invalidateNote(note);
      row['revoked'] = cache.peek(note, attachment.id, 0) == null;
      await cache.close();
      rows.add(row);
    }
  }
  final app = OwnedAppServices(
    environment: StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    ),
  );
  final initialized = await app.initialize();
  final flow = <String, Object?>{'initialized': initialized.isSuccess};
  if (initialized.isSuccess) {
    final editor = ContentViewModel(
      fileService: app.files,
      settings: app.settings,
      encryptionService: EncryptionService(),
      desktopActions: WindowsDesktopActions(),
      startBackgroundServices: false,
    );
    editor.titleController.text = 'Synthetic note';
    editor.quillController.document.insert(0, 'Synthetic body');
    flow['saved'] = (await editor.saveNote()).isSuccess;
    final fixture = File(p.join(run.path, 'new-input.bin'));
    await fixture.writeAsBytes(
      List.generate(448706, (i) => i % 251),
      flush: true,
    );
    flow['attached'] = (await editor.addOwnedAttachment(
      fixture.path,
      'synthetic.bin',
    )).isSuccess;
    if (editor.attachments.isNotEmpty) {
      final opened = await editor.openAttachment(editor.attachments.single);
      flow['opened'] = opened.isSuccess;
      flow['openMessage'] = opened.message;
      if (opened.isSuccess)
        flow['bytesMatch'] = _equal(
          await File(opened.value!.path).readAsBytes(),
          await fixture.readAsBytes(),
        );
      final reference = await app.files.resolveNote(editor.currentFileName!);
      final policies = <Map<String, Object?>>[];
      for (final check in [false, true]) {
        for (final verify in [false, true]) {
          final cache = AttachmentOpenCache(
            rootResolver: () async => root,
            sourceResolver: app.files.attachmentSource,
            sourcePreparer: app.files.attachmentSource,
            performance: () => AttachmentPerformance.defaults.copyWith(
              checkBeforeOpen: check,
              verifyAfterOpen: verify,
            ),
          );
          final result = await cache.prepare(
            reference!,
            editor.attachments.single,
            0,
          );
          policies.add({
            'check': check,
            'verify': verify,
            'opened': result.isSuccess,
            'message': result.message,
          });
          await cache.close();
        }
      }
      flow['policies'] = policies;
      if (const bool.fromEnvironment('FN_UID_PREFLIGHT_PROBE')) {
        final decoded = await NoteCodec.decode(
          (await app.files.readResolved(reference!))!,
          decryptApp: EncryptionService().decryptAppResult,
        );
        final input = await app.files.attachmentSource(
          reference,
          editor.attachments.single.id,
          verifyContent: false,
        );
        var choices = 0;
        String? plainPackage;
        for (final format in ExportFormat.values) {
          for (final password in <String?>[null, 'synthetic-archive']) {
            final package = p.join(run.path, 'uid-$choices.package');
            await StreamingPackService().exportPackage(
              metadata: decoded.metadata,
              attachments: {editor.attachments.single.id: input},
              format: format,
              destination: package,
              operationDirectory: run.path,
              password: password,
            );
            plainPackage ??= package;
            final result = await editor.importNoteFile(
              package,
              archivePassword: password,
              resolveConflict: (_) async {
                final staged = await Directory(app.environment.dataRoot!)
                    .list(recursive: true)
                    .where(
                      (e) =>
                          e is File &&
                          e.path.endsWith('.med') &&
                          p
                              .split(e.path)
                              .any(
                                (n) => n.startsWith('attachment-operation-'),
                              ),
                    )
                    .length;
                if (staged != 0)
                  throw StateError('attachment-extracted-before-choice');
                choices++;
                return NoteImportDecision.ignore;
              },
            );
            if (!result.isSuccess ||
                result.value!.disposition != NoteImportDisposition.ignored) {
              throw StateError('uid-choice-failed');
            }
          }
        }
        for (final decision in [
          NoteImportDecision.duplicate,
          NoteImportDecision.replace,
        ]) {
          final result = await editor.importNoteFile(
            plainPackage!,
            resolveConflict: (_) async => decision,
          );
          if (!result.isSuccess) throw StateError('uid-import-failed');
        }
        flow['uidChoicesBeforeExtraction'] = choices == 4;
        flow['uidDuplicateReplacePassed'] = true;
      }
    }
    await editor.closeAttachmentCache();
    await editor.closeLibraryResources();
    editor.dispose();
    flow['closed'] = (await app.close()).isSuccess;
  }
  final passed =
      flow['opened'] == true &&
      flow['bytesMatch'] == true &&
      (!const bool.fromEnvironment('FN_UID_PREFLIGHT_PROBE') ||
          flow['uidChoicesBeforeExtraction'] == true &&
              flow['uidDuplicateReplacePassed'] == true) &&
      rows.every(
        (r) => [
          'direct',
          'worker',
          'cache',
          'reused',
          'revoked',
        ].every((k) => r[k] == true),
      );
  await File(
    p.join(Directory.current.path, '.validation/desktop-attachment-probe.json'),
  ).writeAsString(
    jsonEncode({'passed': passed, 'cases': rows, 'editorFlow': flow}),
    flush: true,
  );
  // Remove only this disposable probe's known root, never the normal cache.
  if (!p.basename(run.path).startsWith('future-notes-validation-') ||
      !p.isWithin(Directory.systemTemp.path, run.path)) {
    throw StateError('Unexpected validation root');
  }
  await run.delete(recursive: true);
  exit(passed ? 0 : 1);
}

bool _equal(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
