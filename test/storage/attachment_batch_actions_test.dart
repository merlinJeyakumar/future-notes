import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/platform/attachment_batch_export.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/note_codec.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import '../support/validation_directory.dart';

class FailingCipher extends EncryptionService {
  bool fail = false;
  @override
  Future<String> encryptApp(String text) {
    if (fail) throw StateError('Synthetic encryption failure');
    return super.encryptApp(text);
  }
}

class RecordingOutput implements AttachmentBatchExport {
  RecordingOutput(this.root);
  final Directory root;
  final allocated = <String>[];
  final published = <List<String>>[];
  final payloads = <String>[];
  bool accept = true;
  bool failPublish = false;
  Future<void> Function(int)? onAllocate;
  @override
  Future<String> destination(String name) async {
    final directory = await Directory(
      p.join(root.path, 'export-${allocated.length}'),
    ).create();
    final path = p.join(directory.path, p.basename(name));
    allocated.add(path);
    await onAllocate?.call(allocated.length);
    return path;
  }

  @override
  Future<bool> publish(List<String> paths) async {
    published.add(List.of(paths));
    if (failPublish) throw StateError('Synthetic share failure');
    for (final path in paths) {
      payloads.add(await File(path).readAsString());
    }
    return accept;
  }

  @override
  Future<void> cleanup(Iterable<String> paths) async {
    for (final path in paths) {
      if (await File(path).exists()) await File(path).delete();
      if (await File(path).parent.exists()) await File(path).parent.delete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late OwnedAppServices app;
  late ContentViewModel editor;
  late FailingCipher cipher;
  late List<String> ids;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    app = OwnedAppServices(
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: p.join(run.path, 'settings', 'settings.json'),
      ),
    );
    expect((await app.initialize()).isSuccess, isTrue);
    cipher = FailingCipher();
    editor = ContentViewModel(
      fileService: app.files,
      settings: app.settings,
      encryptionService: cipher,
      startBackgroundServices: false,
      onDraftDecision: (_) async => DraftDecision.discard,
    );
    editor.titleController.text = 'Synthetic batch note';
    editor.quillController.document.insert(0, 'Preserve this synthetic body\n');
    expect((await editor.saveNote()).isSuccess, isTrue);
    for (var i = 0; i < 3; i++) {
      final source = File(p.join(run.path, 'input-$i.txt'));
      await source.writeAsString('synthetic payload $i');
      expect(
        (await editor.addOwnedAttachment(
          source.path,
          i < 2 ? 'duplicate.txt' : 'keep.txt',
        )).isSuccess,
        isTrue,
      );
    }
    ids = editor.attachments.map((a) => a.id).toList();
  });
  tearDown(() async {
    editor.dispose();
    await editor.closeLibraryResources();
    expect((await app.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });
  Future<File> noteFile() async =>
      File((await app.files.resolveNote(editor.currentFileName!))!.contentPath);
  Future<Map<String, dynamic>> stored() async => (await NoteCodec.decode(
    await (await noteFile()).readAsString(),
    decryptApp: cipher.decryptAppResult,
  )).metadata;

  test(
    'batch exports once, preserves duplicate names and cleans plaintext after sharing',
    () async {
      final before = await (await noteFile()).readAsBytes();
      final sink = RecordingOutput(run);
      final progress = <AttachmentJobSnapshot>[];
      void watch() {
        for (final job in editor.attachmentJobsNotifier.value) {
          if (job.progress.value.active &&
              job.progress.value.operation == AttachmentJobOperation.export) {
            job.progress.addListener(() => progress.add(job.progress.value));
          }
        }
      }

      editor.attachmentJobsNotifier.addListener(watch);
      final result = await editor.exportAttachments(ids.take(2), output: sink);
      editor.attachmentJobsNotifier.removeListener(watch);
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(sink.published.length, 1);
      expect(sink.published.single.length, 2);
      expect(sink.payloads, ['synthetic payload 0', 'synthetic payload 1']);
      for (var index = 1; index <= 2; index++) {
        expect(
          progress.any(
            (state) =>
                state.phase == AttachmentJobPhase.decrypting &&
                state.bytes > 0 &&
                state.total != null &&
                state.detail == 'File $index of 2 · duplicate.txt',
          ),
          isTrue,
        );
      }
      expect(sink.allocated.map(p.basename), [
        'duplicate.txt',
        'duplicate.txt',
      ]);
      expect(sink.allocated.toSet().length, 2);
      expect(sink.allocated.any((path) => File(path).existsSync()), isFalse);
      expect(await (await noteFile()).readAsBytes(), before);
      expect(editor.hasAttachmentJobs, isFalse);
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.operation,
        AttachmentJobOperation.export,
      );
      expect(
        editor.attachmentJobsNotifier.value.last.progress.value.batch,
        isTrue,
      );
    },
  );
  test(
    'cancel between files never shares a partial selection and joins cleanup',
    () async {
      final sink = RecordingOutput(run);
      sink.onAllocate = (count) async {
        if (count == 2)
          await editor.cancelAttachmentJob(
            editor.attachmentJobsNotifier.value
                .singleWhere((j) => j.progress.value.active)
                .progress
                .value
                .id,
          );
      };
      final result = await editor.exportAttachments(ids, output: sink);
      expect(result.outcome, OperationOutcome.cancelled);
      expect(sink.published, isEmpty);
      expect(sink.allocated.any((path) => File(path).existsSync()), isFalse);
      expect(editor.attachments.length, 3);
      expect(editor.hasAttachmentJobs, isFalse);
    },
  );
  test(
    'cancelling source checking reports cancelled without preparing or sharing files',
    () async {
      final sink = RecordingOutput(run);
      final watched = <AttachmentJobState, void Function()>{};
      final signals = <Future<void>>[];
      var requested = false;
      void changed() {
        for (final state in editor.attachmentJobsNotifier.value) {
          if (!state.progress.value.active ||
              state.progress.value.operation != AttachmentJobOperation.export ||
              watched.containsKey(state))
            continue;
          void progress() {
            if (!requested &&
                state.progress.value.phase == AttachmentJobPhase.preparing) {
              requested = true;
              signals.add(editor.cancelAttachmentJob(state.progress.value.id));
            }
          }

          watched[state] = progress;
          state.progress.addListener(progress);
          progress();
        }
      }

      editor.attachmentJobsNotifier.addListener(changed);
      try {
        final result = await editor.exportAttachments(ids, output: sink);
        await Future.wait(signals);
        expect(requested, isTrue);
        expect(result.outcome, OperationOutcome.cancelled);
        expect(sink.allocated, isEmpty);
        expect(sink.published, isEmpty);
        expect(editor.hasAttachmentJobs, isFalse);
        expect(editor.attachments.length, 3);
      } finally {
        editor.attachmentJobsNotifier.removeListener(changed);
        for (final entry in watched.entries) {
          entry.key.progress.removeListener(entry.value);
        }
      }
    },
  );
  for (final failed in [false, true]) {
    test(
      'dismissed/failed share cleans the entire prepared batch ($failed)',
      () async {
        final sink = RecordingOutput(run)
          ..accept = false
          ..failPublish = failed;
        final result = await editor.exportAttachments(
          ids.take(2),
          output: sink,
        );
        expect(
          result.outcome,
          failed ? OperationOutcome.ioFailure : OperationOutcome.cancelled,
        );
        expect(sink.allocated.any((path) => File(path).existsSync()), isFalse);
        expect(editor.attachments.length, 3);
      },
    );
  }
  test(
    'bulk removal publishes one generation and retains recoverable objects',
    () async {
      final before = await stored();
      final reference = (await app.files.resolveNote(editor.currentFileName!))!;
      final result = await editor.removeAttachments(ids.take(2));
      expect(result.isSuccess, isTrue, reason: result.message);
      final after = await stored();
      expect(editor.attachments.map((a) => a.id), [ids.last]);
      expect((after['attachments'] as List).map((a) => a['id']), [ids.last]);
      for (final field in ['id', 'content', 'timestamp']) {
        expect(after[field], before[field]);
      }
      for (final id in ids) {
        expect(
          await File(p.join(reference.attachmentLocation, '$id.med')).exists(),
          isTrue,
        );
      }
    },
  );
  test(
    'failed/invalid removal leaves every selected attachment and envelope unchanged',
    () async {
      final before = await (await noteFile()).readAsBytes();
      expect(
        (await editor.removeAttachments([ids.first, 'missing'])).isSuccess,
        isFalse,
      );
      cipher.fail = true;
      final result = await editor.removeAttachments(ids.take(2));
      expect(result.isSuccess, isFalse);
      expect(editor.attachments.map((a) => a.id), ids);
      expect(await (await noteFile()).readAsBytes(), before);
    },
  );
  test(
    'locked/active-job guards reject a bulk selection without preparing output',
    () async {
      final sink = RecordingOutput(run);
      final job = AttachmentJobState(
        AttachmentJobSnapshot(
          id: 'guard-job',
          owner: editor.draftSession.generation,
          fileName: 'synthetic guard',
          phase: AttachmentJobPhase.encrypting,
        ),
      );
      editor.attachmentJobsNotifier.value = [job];
      expect((await editor.removeAttachments(ids.take(2))).isSuccess, isFalse);
      editor.attachmentJobsNotifier.value = [];
      job.dispose();
      expect(
        (await editor.setPassword('synthetic-password')).isSuccess,
        isTrue,
      );
      final lockedIds = editor.attachments.map((a) => a.id).toList();
      expect((await editor.manualLock()).isSuccess, isTrue);
      expect(
        (await editor.exportAttachments(lockedIds, output: sink)).isSuccess,
        isFalse,
      );
      expect((await editor.removeAttachments(lockedIds)).isSuccess, isFalse);
      expect(sink.allocated, isEmpty);
    },
  );
}
