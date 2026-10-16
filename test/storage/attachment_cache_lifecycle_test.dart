import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import '../support/validation_directory.dart';
import 'owned_mutation_integration_test.dart' show PausedEncryption;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late OwnedAppServices app;
  late AttachmentOpenCache cache;
  late ContentViewModel editor;
  late PausedEncryption cipher;
  final decisions = <DraftDecisionRequest>[];
  var decision = DraftDecision.cancel;
  setUp(() async {
    decisions.clear();
    decision = DraftDecision.cancel;
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    app = OwnedAppServices(
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
    );
    expect((await app.initialize()).isSuccess, isTrue);
    final root = await Directory(p.join(run.path, 'cache')).create();
    cache = AttachmentOpenCache(
      rootResolver: () async => root.path,
      sourceResolver: app.files.attachmentSource,
    );
    cipher = PausedEncryption();
    editor = ContentViewModel(
      fileService: app.files,
      settings: app.settings,
      encryptionService: cipher,
      attachmentOpenCache: cache,
      startBackgroundServices: false,
      onDraftDecision: (request) async {
        decisions.add(request);
        return decision;
      },
    );
  });
  tearDown(() async {
    await editor.closeAttachmentCache();
    editor.dispose();
    await editor.closeLibraryResources();
    expect((await app.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });
  Future<void> saveWithAttachment() async {
    editor.titleController.text = 'synthetic note';
    editor.quillController.document.insert(0, 'synthetic body');
    expect((await editor.saveNote()).isSuccess, isTrue);
    final source = File(p.join(run.path, 'source.txt'));
    await source.writeAsString('synthetic attachment', flush: true);
    expect(
      (await editor.addOwnedAttachment(source.path, 'sample.txt')).isSuccess,
      isTrue,
    );
  }

  Future<String> open() async {
    final result = await editor.openAttachment(editor.attachments.single);
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(
      await File(result.value!.path).readAsString(),
      'synthetic attachment',
    );
    return result.value!.path;
  }

  test(
    'navigation reuses cache; lock, rekey, removal and Delete revoke it',
    () async {
      await saveWithAttachment();
      final first = await open();
      final name = editor.currentFileName!;
      expect((await editor.reset()).isSuccess, isTrue);
      expect((await editor.loadNote(name)).isSuccess, isTrue);
      expect(await open(), first);
      expect(cache.transformCount, 1);
      expect(
        (await editor.setPassword('synthetic-password')).isSuccess,
        isTrue,
      );
      expect(await File(first).exists(), isFalse);
      final protected = await open();
      final protectedTransforms = cache.transformCount;
      expect((await editor.reset()).isSuccess, isTrue);
      expect((await editor.loadNote(name)).isSuccess, isTrue);
      expect(editor.isLocked, isFalse);
      expect(
        editor.cachedAttachment(editor.attachments.single.id)?.path,
        protected,
      );
      editor.quillController.document.insert(0, 'typed without relocking ');
      expect((await editor.saveNote()).isSuccess, isTrue);
      expect(await open(), protected);
      expect(cache.transformCount, protectedTransforms);
      expect((await editor.manualLock()).isSuccess, isTrue);
      expect(await File(protected).exists(), isFalse);
      expect(editor.cachedAttachment(editor.attachments.single.id), isNull);
      expect(await editor.unlockNote('synthetic-password'), isTrue);
      final unlocked = await open();
      expect(
        (await editor.changePasswordResult('next-password')).isSuccess,
        isTrue,
      );
      expect(await File(unlocked).exists(), isFalse);
      final rekeyed = await open();
      final rekeyedTransforms = cache.transformCount;
      expect((await editor.reset()).isSuccess, isTrue);
      expect((await editor.loadNote(name)).isSuccess, isTrue);
      expect(await open(), rekeyed);
      expect(cache.transformCount, rekeyedTransforms);
      expect(
        (await editor.removeAttachment(editor.attachments.single.id)).isSuccess,
        isTrue,
      );
      expect(await File(rekeyed).exists(), isFalse);
      final source = File(p.join(run.path, 'source.txt'));
      expect(
        (await editor.addOwnedAttachment(source.path, 'sample.txt')).isSuccess,
        isTrue,
      );
      final removable = await open();
      final reviewed = await editor.reviewDeletion(editor.currentFileName!);
      expect(reviewed, isNotNull);
      expect((await editor.deleteReviewedNote(reviewed!)).isSuccess, isTrue);
      expect(await File(removable).exists(), isFalse);
      expect(editor.currentFileName, isNull);
    },
  );

  test('actual cache close removes files from every unlocked note', () async {
    await saveWithAttachment();
    final first = await open();
    expect((await editor.reset()).isSuccess, isTrue);
    await saveWithAttachment();
    final second = await open();
    expect(first, isNot(second));
    expect(await File(first).exists(), isTrue);
    expect(await File(second).exists(), isTrue);
    await editor.closeAttachmentCache();
    expect(await File(first).exists(), isFalse);
    expect(await File(second).exists(), isFalse);
  });

  test(
    'actual Exit offers keep running or cancellation during preparation',
    () async {
      await saveWithAttachment();
      final source = File(p.join(run.path, 'large-synthetic.bin'));
      final file = await source.open(mode: FileMode.writeOnly);
      await file.truncate(16 * 1024 * 1024);
      await file.close();
      final count = editor.attachments.length;
      final adding = editor.addOwnedAttachment(source.path, 'pending.bin');
      expect(editor.hasAttachmentJobs, isTrue);
      expect(
        (await editor.prepareToExit()).outcome,
        OperationOutcome.cancelled,
      );
      expect(decisions.single.kind, DraftDecisionKind.activeAttachments);
      expect(decisions.single.transition, DraftTransition.exit);
      decision = DraftDecision.discard;
      expect((await editor.prepareToExit()).isSuccess, isTrue);
      expect((await adding).outcome, OperationOutcome.cancelled);
      expect(editor.attachments.length, count);
      expect(editor.hasAttachmentJobs, isFalse);
    },
  );

  test(
    'actual Exit waits for publication without offering cancellation',
    () async {
      await saveWithAttachment();
      final (reached, release) = cipher.pause();
      final adding = editor.addOwnedAttachment(
        p.join(run.path, 'source.txt'),
        'finalizing.txt',
      );
      await reached.timeout(const Duration(seconds: 15));
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.phase,
        AttachmentJobPhase.finalizing,
      );
      var exited = false;
      final exiting = editor.prepareToExit().then((result) {
        exited = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(exited, isFalse);
      expect(decisions, isEmpty);
      release.complete();
      expect((await adding).isSuccess, isTrue);
      expect((await exiting).isSuccess, isTrue);
      expect(editor.attachments.length, 2);
    },
  );
}
