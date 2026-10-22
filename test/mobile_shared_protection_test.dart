import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/file_operation_progress.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import 'support/editor_harness.dart';

class _SharePayloadFiles extends MemoryNoteFiles
    implements MobileSharePersistence, TransactionalNoteFiles {
  _SharePayloadFiles(super.libraryRoot, this.payloadRoot);
  final Directory payloadRoot;
  final payloads = <String, File>{};

  @override
  bool get supportsBackgroundIntake => true;
  @override
  bool get usesOwnedStorage => true;
  @override
  Future<List<NoteReference>> pendingDeletions() async => [];
  @override
  Future<Directory> createOperationDirectory(NoteReference reference) =>
      payloadRoot.createTemp('operation-');
  @override
  Future<void> removeOperationDirectory(Directory operation) async {
    if (!p.isWithin(payloadRoot.path, operation.path)) {
      throw StateError('Unowned synthetic operation.');
    }
    await operation.delete(recursive: true);
  }

  @override
  Future<StreamingFileSource> attachmentSource(
    NoteReference reference,
    String id, {
    FileByteProgress? onProgress,
    dynamic cancellation,
    bool verifyContent = true,
  }) async {
    final file = payloads[id]!;
    return StreamingFileSource(file.path, await file.length());
  }

  @override
  Future<NoteReference> commitGeneration(
    NoteReference reference,
    String content,
    List<PreparedAttachmentFile> attachments, {
    FileByteProgress? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  }) async {
    if (failWrites) throw const FileSystemException('Synthetic commit failure');
    for (final attachment in attachments) {
      payloads[attachment.id] = await File(
        attachment.source.path,
      ).copy(p.join(payloadRoot.path, '${attachment.id}.med'));
    }
    return writeResolved(reference, content);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failFirstCommit in [false, true]) {
    test(
      'shared attachments keep one active generation through protection, failFirstCommit=$failFirstCommit',
      () async {
        final h = await EditorHarness.create();
        final root = await Directory(p.join(h.run.path, 'payloads')).create();
        final files = _SharePayloadFiles(h.files.libraryRoot, root);
        final model = ContentViewModel(
          fileService: files,
          encryptionService: h.encryption,
          settings: h.settings,
          startBackgroundServices: false,
        );
        Future<void> expectPayload(String? password) async {
          final attachment = model.attachments.single;
          final output = File(p.join(root.path, 'decoded.bin'));
          final source = await files.attachmentSource(
            (await files.resolveNote(model.currentFileName!))!,
            attachment.id,
          );
          await StreamingFileCipher.transform(
            source: source,
            destination: output.path,
            decryptSource: true,
            encryptDestination: false,
            sourcePassword: password,
            verifyOutput: false,
          );
          expect(await output.readAsBytes(), [1, 2, 3, 4]);
          await output.delete();
          expect(attachment.mentionId, 'stable-shared-mention');
        }

        try {
          final target = await model.createSharedNote('Synthetic shared', null);
          expect(
            (await model.loadNote(target.reference.fileName)).isSuccess,
            true,
          );
          final input = await File(
            p.join(root.path, 'source.bin'),
          ).writeAsBytes([1, 2, 3, 4]);
          final encrypted = File(p.join(root.path, 'encrypted.med'));
          await StreamingFileCipher.transform(
            source: StreamingFileSource(input.path, 4),
            destination: encrypted.path,
            decryptSource: false,
            encryptDestination: true,
            verifyOutput: false,
            ownedTarget: OwnedWriteTarget.forPath(encrypted.path),
          );
          await model.commitSharedAttachment(
            target,
            AttachmentModel(
              id: 'shared-original',
              fileName: 'shared.bin',
              size: 4,
              mentionId: 'stable-shared-mention',
            ),
            PreparedAttachmentFile(
              'shared-original',
              StreamingFileSource(encrypted.path, await encrypted.length()),
            ),
            cancelled: () => false,
          );
          if (failFirstCommit) {
            files.failWrites = true;
            expect(
              (await model.setPassword('synthetic-password')).isSuccess,
              false,
            );
            expect(model.isPasswordSet, false);
            expect(model.attachments.single.id, 'shared-original');
            await expectPayload(null);
            files.failWrites = false;
          }
          expect(
            (await model.setPassword('synthetic-password')).isSuccess,
            true,
          );
          expect(model.attachments, hasLength(1));
          expect(model.attachments.single.id, isNot('shared-original'));
          await expectPayload('synthetic-password');
          expect((await model.clearPassword()).isSuccess, true);
          expect(model.attachments, hasLength(1));
          await expectPayload(null);
          expect(
            (await model.loadNote(target.reference.fileName)).isSuccess,
            true,
          );
          expect(model.attachments, hasLength(1));
        } finally {
          model.dispose();
          await model.closeLibraryResources();
          await h.dispose();
        }
      },
    );
  }
}
