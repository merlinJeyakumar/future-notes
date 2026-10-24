import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/attachment_thumbnail_source.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/attachment_thumbnail_codec.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'support/thumbnail_fixture.dart';
import 'support/validation_directory.dart';

class ThumbnailFiles extends FileService implements AttachmentThumbnailSource {
  ThumbnailFiles({required super.settings, required super.storageOwner});
  bool generate = true;
  bool cachedAvailable = true;
  int picked = 0, cached = 0;
  Completer<void>? refreshStarted, refreshGate;
  @override
  bool get supportsAttachmentThumbnails => true;
  @override
  Future<Uint8List?> thumbnailFromPickedSource(String path, String name) async {
    picked++;
    return generate ? thumbnailFixture() : null;
  }

  @override
  Future<Uint8List?> thumbnailFromCachedFile(String path, String name) async {
    cached++;
    refreshStarted?.complete();
    await refreshGate?.future;
    return cachedAvailable ? thumbnailFixture() : null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cipher = EncryptionService(useNative: false);
  test(
    'thumbnail is encrypted, bounded, rekeyable and optional on legacy models',
    () async {
      final jpeg = thumbnailFixture();
      final sealed = (await AttachmentThumbnailCodec.seal(
        jpeg,
        cipher,
        'old',
      ))!;
      expect(sealed, isNot(contains(base64Encode(jpeg))));
      expect(await AttachmentThumbnailCodec.open(sealed, cipher, 'old'), jpeg);
      expect(
        await AttachmentThumbnailCodec.open(sealed, cipher, 'wrong'),
        isNull,
      );
      final next = await AttachmentThumbnailCodec.rekey(
        sealed,
        cipher,
        'old',
        'new',
      );
      expect(await AttachmentThumbnailCodec.open(next, cipher, 'new'), jpeg);
      expect(await AttachmentThumbnailCodec.open(next, cipher, 'old'), isNull);
      expect(
        await AttachmentThumbnailCodec.open('v1:broken', cipher, null),
        isNull,
      );
      expect(
        AttachmentModel(
          id: 'legacy',
          fileName: 'old',
        ).toJson().containsKey('encryptedThumbnail'),
        false,
      );
      final model = AttachmentModel(
        id: 'a',
        fileName: 'a.mp4',
        encryptedThumbnail: sealed,
      );
      expect(
        AttachmentModel.fromJson(model.toJson()).encryptedThumbnail,
        sealed,
      );
      final oversized = Uint8List.fromList(jpeg)
        ..[jpeg.indexOf(0xc0) + 7] = 255;
      expect(AttachmentThumbnailCodec.validJpeg(oversized), false);
    },
  );

  late Directory run;
  late OwnedAppServices app;
  late ThumbnailFiles files;
  late ContentViewModel editor;
  late AttachmentOpenCache cache;
  String? failedAttachment;
  setUp(() async {
    failedAttachment = null;
    run = await createValidationRun();
    app = OwnedAppServices(
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: '${run.path}/library',
        settingsFile: '${run.path}/settings/config.json',
      ),
      createFiles: (settings, owner) =>
          files = ThumbnailFiles(settings: settings, storageOwner: owner),
    );
    expect((await app.initialize()).isSuccess, true);
    await Directory('${run.path}/cache').create();
    cache = AttachmentOpenCache(
      rootResolver: () async => '${run.path}/cache',
      sourceResolver: (note, id) async => id == failedAttachment
          ? StreamingFileSource('${run.path}/unreadable-fixture.med', 3)
          : files.attachmentSource(note, id),
    );
    editor = ContentViewModel(
      fileService: files,
      settings: app.settings,
      encryptionService: cipher,
      attachmentOpenCache: cache,
      startBackgroundServices: false,
    );
  });
  tearDown(() async {
    await editor.closeAttachmentCache();
    editor.dispose();
    await editor.closeLibraryResources();
    await app.close();
    await deleteValidationRun(run);
  });
  Future<void> attach() async {
    editor.titleController.text = 'Synthetic thumbnail note';
    expect((await editor.saveNote()).isSuccess, true);
    final input = await File(
      '${run.path}/source.jpg',
    ).writeAsBytes(thumbnailFixture());
    expect(
      (await editor.addOwnedAttachment(input.path, 'source.jpg')).isSuccess,
      true,
    );
  }

  test(
    'intake stores thumbnail; unlock restores without payload transformation; password changes preserve it',
    () async {
      await attach();
      expect(files.picked, 1);
      expect(cache.transformCount, 0);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        thumbnailFixture(),
      );
      final path = editor.currentFileName!;
      expect((await editor.setPassword('synthetic-password')).isSuccess, true);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        thumbnailFixture(),
      );
      await editor.manualLock();
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        isNull,
      );
      expect(await editor.unlockNote('synthetic-password'), true);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        thumbnailFixture(),
      );
      expect(cache.transformCount, 0);
      expect((await editor.clearPassword()).isSuccess, true);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        thumbnailFixture(),
      );
      expect((await editor.loadNote(path)).isSuccess, true);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        thumbnailFixture(),
      );
      expect(cache.transformCount, 0);
    },
  );

  test(
    'legacy refresh decrypts once then reuses the stored thumbnail',
    () async {
      files.generate = false;
      await attach();
      expect(editor.attachments.single.encryptedThumbnail, isNull);
      expect(cache.transformCount, 0);
      expect((await editor.refreshAttachmentThumbnails()).isSuccess, true);
      expect(cache.transformCount, 1);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments.single),
        thumbnailFixture(),
      );
      expect((await editor.refreshAttachmentThumbnails()).isSuccess, true);
      expect(cache.transformCount, 1);
      expect(files.cached, 1);
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.operation,
        AttachmentJobOperation.thumbnail,
      );
    },
  );

  test(
    'refresh reuses a valid stored thumbnail without opening payload/cache',
    () async {
      await attach();
      expect(cache.transformCount, 0);
      expect((await editor.refreshAttachmentThumbnails()).isSuccess, true);
      expect(cache.transformCount, 0);
      expect(files.cached, 0);
    },
  );
  test(
    'explicit refresh replaces video thumbnail and reuses plaintext cache',
    () async {
      editor.titleController.text = 'Synthetic video';
      expect((await editor.saveNote()).isSuccess, true);
      final input = await File(
        '${run.path}/source.mp4',
      ).writeAsBytes([1, 2, 3]);
      expect(
        (await editor.addOwnedAttachment(input.path, 'source.mp4')).isSuccess,
        true,
      );
      final before = editor.attachments.single.encryptedThumbnail;
      expect((await editor.refreshAttachmentThumbnails()).isSuccess, true);
      expect(files.cached, 1);
      expect(editor.attachments.single.encryptedThumbnail, isNot(before));
      expect(cache.transformCount, 1);
      expect((await editor.refreshAttachmentThumbnails()).isSuccess, true);
      expect(files.cached, 2);
      expect(cache.transformCount, 1);
      final retained = editor.attachments.single.encryptedThumbnail;
      files.cachedAvailable = false;
      expect((await editor.refreshAttachmentThumbnails()).isSuccess, false);
      expect(editor.attachments.single.encryptedThumbnail, retained);
    },
  );
  test(
    'failed generation cannot report that thumbnails were refreshed',
    () async {
      files.generate = false;
      files.cachedAvailable = false;
      await attach();
      final result = await editor.refreshAttachmentThumbnails();
      expect(result.isSuccess, false);
      expect(result.message, contains('this image'));
      expect(result.message, contains('Existing thumbnails were kept'));
      expect(editor.attachments.single.encryptedThumbnail, isNull);
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.phase,
        AttachmentJobPhase.failed,
      );
    },
  );

  test(
    'one unreadable video does not discard generated image and video thumbnails',
    () async {
      files.generate = false;
      await attach();
      final input = '${run.path}/source.jpg';
      expect(
        (await editor.addOwnedAttachment(
          input,
          'readable-video.mp4',
        )).isSuccess,
        true,
      );
      expect(
        (await editor.addOwnedAttachment(
          input,
          'unreadable-video.mp4',
        )).isSuccess,
        true,
      );
      final ids = editor.attachments.map((a) => a.id).toList();
      failedAttachment = ids.last;
      await File('${run.path}/unreadable-fixture.med').writeAsBytes([1, 2, 3]);
      final result = await editor.refreshAttachmentThumbnails();
      expect(result.isSuccess, true, reason: result.message);
      expect(editor.attachments.map((a) => a.id), ids);
      expect(
        editor.attachments.where((a) => a.encryptedThumbnail != null),
        hasLength(2),
      );
      expect(editor.attachments.last.encryptedThumbnail, isNull);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments[1]),
        thumbnailFixture(),
      );
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.detail,
        contains('2 thumbnails refreshed'),
      );
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.detail,
        contains('1 could not be created'),
      );
      final name = editor.currentFileName!;
      expect((await editor.loadNote(name)).isSuccess, true);
      expect(
        await editor.restoreAttachmentThumbnail(editor.attachments[1]),
        thumbnailFixture(),
      );
    },
  );

  test(
    'cancelled refresh does not publish metadata or overwrite an edit',
    () async {
      files.generate = false;
      await attach();
      files.refreshStarted = Completer<void>();
      files.refreshGate = Completer<void>();
      final refresh = editor.refreshAttachmentThumbnails();
      await files.refreshStarted!.future.timeout(const Duration(seconds: 15));
      editor.titleController.text = 'Edited while refreshing';
      final job = editor.attachmentJobsNotifier.value.last.progress.value;
      expect(job.operation, AttachmentJobOperation.thumbnail);
      await editor.cancelAttachmentJob(job.id);
      files.refreshGate!.complete();
      expect((await refresh).isSuccess, false);
      expect(editor.attachments.single.encryptedThumbnail, isNull);
      expect(editor.titleController.text, 'Edited while refreshing');
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.phase,
        AttachmentJobPhase.cancelled,
      );
    },
  );

  for (final format in ExportFormat.values) {
    for (final archivePassword in <String?>[null, 'archive-demo']) {
      test(
        'stored thumbnail survives $format package password=$archivePassword',
        () async {
          await attach();
          final attachment = editor.attachments.single;
          final metadata = {
            'id': 'synthetic',
            'title': 'Synthetic',
            'content': ' body\n',
            'isLocked': false,
            'timestamp': 1700000000000,
            'attachments': [attachment.toJson()],
            'unknown': {'preserve': true},
          };
          final reference = (await files.resolveNote(editor.currentFileName!))!;
          final source = await files.attachmentSource(reference, attachment.id);
          final output =
              '${run.path}/synthetic.${format == ExportFormat.zip ? 'zip' : 'fnote'}';
          final operations = await Directory('${run.path}/pack').create();
          const pack = StreamingPackService(useNative: false);
          await pack.exportPackage(
            metadata: metadata,
            attachments: {attachment.id: source},
            format: format,
            destination: output,
            operationDirectory: operations.path,
            password: archivePassword,
          );
          final extracted = await Directory('${run.path}/extracted').create();
          final imported = await pack.importPackage(
            source: output,
            operationDirectory: extracted.path,
            password: archivePassword,
          );
          expect(
            imported.note.note.attachments.single.encryptedThumbnail,
            attachment.encryptedThumbnail,
          );
          expect(imported.note.metadata['unknown'], {'preserve': true});
          expect(
            await AttachmentThumbnailCodec.open(
              imported.note.note.attachments.single.encryptedThumbnail,
              cipher,
              null,
            ),
            thumbnailFixture(),
          );
        },
      );
    }
  }
}
