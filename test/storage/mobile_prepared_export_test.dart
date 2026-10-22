import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/platform/prepared_mobile_export.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import '../support/validation_directory.dart';

class MobilePackageModel extends ContentViewModel {
  MobilePackageModel(OwnedAppServices app)
    : super(
        fileService: app.files,
        settings: app.settings,
        encryptionService: EncryptionService(),
        startBackgroundServices: false,
      );
  @override
  bool get prepareMobilePackageExport => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unchanged mobile packages reuse the owned file; edits/options/lock invalidate reuse',
    () async {
      final run = await createValidationRun();
      final cache = await Directory(p.join(run.path, 'cache')).create();
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => cache.path);
      final app = OwnedAppServices(
        environment: StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: p.join(run.path, 'library'),
          settingsFile: p.join(run.path, 'configuration', 'settings.json'),
        ),
      );
      expect((await app.initialize()).isSuccess, isTrue);
      final editor = MobilePackageModel(app);
      Future<PreparedMobileExport> prepare({
        ExportFormat format = ExportFormat.binary,
        String? password,
      }) async {
        final result = await editor.exportNotePack(
          format: format,
          password: password,
        );
        expect(result.isSuccess, isTrue, reason: result.message);
        return editor.preparedExportForJob(
          editor.attachmentJobsNotifier.value.last.progress.value.id,
        )!;
      }

      try {
        editor.titleController.text = 'Synthetic note';
        editor.quillController.document.insert(0, 'Synthetic body');
        expect((await editor.saveNote()).isSuccess, isTrue);
        final source = await File(
          p.join(run.path, 'input'),
        ).writeAsString('Synthetic file');
        expect(
          (await editor.addOwnedAttachment(
            source.path,
            'synthetic.txt',
          )).isSuccess,
          isTrue,
        );
        final first = await prepare();
        expect(p.basename(first.path), 'Synthetic note.fnote');
        final repeated = await prepare();
        expect(repeated, same(first));
        expect(
          editor.attachmentJobsNotifier.value.last.progress.value.detail,
          'Using prepared export',
        );
        expect(await first.isCurrent(), isTrue);
        final ref = (await app.files.resolveNote(editor.currentFileName!))!;
        final encrypted = await app.files.attachmentSource(
          ref,
          editor.attachments.single.id,
          verifyContent: false,
        );
        final encryptedFile = File(encrypted.path);
        final previousDate = await encryptedFile.lastModified();
        await encryptedFile.setLastModified(
          previousDate.add(const Duration(seconds: 2)),
        );
        final changedSource = await prepare();
        expect(changedSource.path, isNot(first.path));
        expect(await File(first.path).exists(), isFalse);
        editor.quillController.document.insert(0, 'Changed ');
        expect((await editor.saveNote()).isSuccess, isTrue);
        final changed = await prepare();
        expect(changed.path, isNot(changedSource.path));
        expect(await File(changedSource.path).exists(), isFalse);
        final zip = await prepare(format: ExportFormat.zip);
        expect(zip.path, isNot(changed.path));
        final protected = await prepare(
          format: ExportFormat.zip,
          password: 'synthetic-archive',
        );
        expect(protected.path, isNot(zip.path));
        expect(
          await prepare(
            format: ExportFormat.zip,
            password: 'synthetic-archive',
          ),
          same(protected),
        );
        final otherPassword = await prepare(
          format: ExportFormat.zip,
          password: 'synthetic-other',
        );
        expect(otherPassword.path, isNot(protected.path));
        await File(otherPassword.path).delete();
        final rebuilt = await prepare(
          format: ExportFormat.zip,
          password: 'synthetic-other',
        );
        expect(rebuilt, isNot(same(otherPassword)));
        expect((await editor.setPassword('synthetic-note')).isSuccess, isTrue);
        final beforeLock = await prepare();
        expect((await editor.manualLock()).isSuccess, isTrue);
        expect(await File(beforeLock.path).exists(), isFalse);
      } finally {
        await editor.closeAttachmentCache();
        editor.dispose();
        await editor.closeLibraryResources();
        expect((await app.close()).isSuccess, isTrue);
        messenger.setMockMethodCallHandler(paths, null);
        await deleteValidationRun(run);
      }
    },
  );
}
