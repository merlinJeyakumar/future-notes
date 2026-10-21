import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/decryption_result.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import '../support/validation_directory.dart';

class PausedExportCipher extends EncryptionService {
  final reached = Completer<void>();
  final release = Completer<void>();
  bool pause = false;
  @override
  Future<DecryptionResult<String>> decryptAppResult(String text) async {
    if (pause) {
      pause = false;
      reached.complete();
      await release.future;
    }
    return super.decryptAppResult(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unlocking read-only does not cancel or change a real protected export',
    () async {
      final run = await createValidationRun();
      final app = OwnedAppServices(
        environment: StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: p.join(run.path, 'library'),
          settingsFile: p.join(run.path, 'configuration', 'settings.json'),
        ),
      );
      expect((await app.initialize()).isSuccess, isTrue);
      final cipher = PausedExportCipher();
      final editor = ContentViewModel(
        fileService: app.files,
        settings: app.settings,
        encryptionService: cipher,
        startBackgroundServices: false,
      );
      Future<dynamic>? exporting;
      try {
        editor.titleController.text = 'Synthetic protected note';
        editor.quillController.document.insert(0, 'Synthetic protected body');
        expect((await editor.saveNote()).isSuccess, isTrue);
        expect(
          (await editor.setPassword('synthetic-password')).isSuccess,
          isTrue,
        );
        expect((await editor.manualLock()).isSuccess, isTrue);
        final reference = (await app.files.resolveNote(
          editor.currentFileName!,
        ))!;
        final before = await File(reference.contentPath).readAsBytes();
        final owner = editor.draftSession.generation;
        final destination = p.join(run.path, 'export.fnote');
        cipher.pause = true;
        exporting = editor.exportOwnedPackageTo(
          destination,
          format: ExportFormat.binary,
        );
        await cipher.reached.future.timeout(const Duration(seconds: 15));
        expect(editor.hasActiveExport, isTrue);
        expect(await editor.unlockNote('wrong', readOnlyExport: true), isFalse);
        expect(
          await editor.unlockNote('synthetic-password', readOnlyExport: true),
          isTrue,
        );
        expect(editor.draftSession.generation, owner);
        expect(editor.quillController.readOnly, isTrue);
        expect(editor.hasActiveExport, isTrue);
        cipher.release.complete();
        final result = await exporting.timeout(const Duration(seconds: 20));
        expect(result.isSuccess, isTrue, reason: result.message);
        final unpack = await Directory(p.join(run.path, 'unpack')).create();
        final imported = await StreamingPackService().importPackage(
          source: destination,
          operationDirectory: unpack.path,
        );
        expect(imported.note.note.isLocked, isTrue);
        final body = await cipher.decryptResult(
          imported.note.note.content,
          password: 'synthetic-password',
        );
        expect(body.isSuccess, isTrue);
        expect(body.value, contains('Synthetic protected body'));
        expect(await File(reference.contentPath).readAsBytes(), before);
      } finally {
        if (!cipher.release.isCompleted) cipher.release.complete();
        await exporting;
        editor.dispose();
        await editor.closeLibraryResources();
        expect((await app.close()).isSuccess, isTrue);
        await deleteValidationRun(run);
      }
    },
  );
}
