import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_application_1/core/platform/additional_mobile_jobs.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/mobile_job_binding.dart';
import 'package:flutter_application_1/core/platform/incoming_share_inbox.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/core/storage/file_operation_progress.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/models/shared_attachment_target.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/mobile/incoming_share_screen.dart';
import 'package:flutter_application_1/features/dashboard/mobile/shared_attachment_jobs.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'package:flutter_application_1/features/dashboard/widgets/background_tasks_dialog.dart';
import 'support/editor_harness.dart';

class ShareFiles extends MemoryNoteFiles
    implements MobileSharePersistence, TransactionalNoteFiles {
  ShareFiles(super.libraryRoot);
  @override
  bool get supportsBackgroundIntake => true;
  @override
  bool get usesOwnedStorage => true;
  @override
  Future<List<NoteReference>> pendingDeletions() async => [];
  @override
  Future<NoteReference> commitGeneration(
    NoteReference reference,
    String content,
    List<PreparedAttachmentFile> attachments, {
    FileByteProgress? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  }) => writeResolved(reference, content);
}

class UnusedProviderFiles extends Fake implements ProviderNoteFiles {}

class ImportProviderFiles extends UnusedProviderFiles {
  final adopted = <String>[];
  bool reject = false;
  @override
  PlatformFile adoptDroppedSource(Map<Object?, Object?> source) {
    adopted.add(source['lease'] as String);
    if (reject) throw StateError('Synthetic closed provider');
    return PlatformFile(
      name: source['name'] as String,
      path: source['path'] as String,
      size: source['length'] as int,
    );
  }
}

class ExtraJobs implements AdditionalMobileJobs {
  @override
  final ValueNotifier<List<AttachmentJobState>> jobs = ValueNotifier([]);
  final cancelled = <String>[];
  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }

  @override
  Map<String, Object?>? recovery(String id) => {
    'target': 'synthetic',
    'library': 'validation',
  };
}

class DeferredShareDiscovery implements LibraryDiscovery {
  final snapshots = StreamController<DiscoverySnapshot>.broadcast(sync: true);
  final failures = StreamController<DiscoveryFailureEvent>.broadcast(
    sync: true,
  );
  DiscoveryRequest? desired;
  int requests = 0;
  bool closed = false;
  @override
  bool get isReady => !closed;
  @override
  DiscoveryRequest? get requestedScan => desired;
  @override
  Stream<DiscoverySnapshot> get discoveriesStream => snapshots.stream;
  @override
  Stream<DiscoveryFailureEvent> get failuresStream => failures.stream;
  @override
  Future<void> init() async {}
  @override
  bool isCurrent(DiscoveryRequest request) =>
      !closed && desired?.matches(request) == true;
  @override
  void invalidateRequests() => desired = null;
  @override
  void loadRecentFiles(String directoryPath) =>
      desired = DiscoveryRequest(directoryPath, 1, ++requests);
  void publish(List<RecentFile> files, {bool isFinal = true}) =>
      snapshots.add(DiscoverySnapshot(desired!, files, isFinal: isFinal));
  @override
  void dispose() {
    closed = true;
    snapshots.close();
    failures.close();
  }
}

class DiscoveryShareFiles extends MemoryNoteFiles {
  DiscoveryShareFiles(super.libraryRoot);
  @override
  Stream<void> watchRecentFiles() => const Stream.empty();
}

class ShareDiscoverySettings extends SettingsService {
  ShareDiscoverySettings(SettingsService source)
    : super.withStorage(storage: source.storageEnvironment);
  @override
  Future<void> init() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final initiallyLoaded in [false, true]) {
    testWidgets(
      'share destinations follow discovery initiallyLoaded=$initiallyLoaded without interaction',
      (tester) async {
        final h = await EditorHarness.create();
        final settings = ShareDiscoverySettings(h.settings);
        final discovery = DeferredShareDiscovery();
        final files = DiscoveryShareFiles(h.files.libraryRoot);
        final model = ContentViewModel(
          fileService: files,
          encryptionService: h.encryption,
          settings: settings,
          backgroundService: discovery,
        );
        final jobs = SharedAttachmentJobs(
          model: model,
          files: UnusedProviderFiles(),
          settings: h.settings,
          inbox: IncomingShareInbox(
            channel: const MethodChannel('validation/share-discovery'),
          ),
        );
        RecentFile note(String name) => RecentFile(
          path: '$name.enc',
          fullPath: h.files.reference('$name.enc').contentPath,
          title: name,
          noteId: name,
        );
        try {
          await tester.pump();
          expect(discovery.requests, 1);
          if (initiallyLoaded) discovery.publish([note('Synthetic Alpha')]);
          await tester.pumpWidget(
            MaterialApp(
              home: IncomingShareScreen(
                batch: IncomingSharedBatch('synthetic', [
                  {'name': 'random.bin', 'length': 16},
                ], null),
                jobs: jobs,
                model: model,
              ),
            ),
          );
          await tester.pump();
          if (!initiallyLoaded) {
            expect(find.text('Loading notes…'), findsOneWidget);
            expect(find.text('No matching notes'), findsNothing);
            discovery.publish([note('Synthetic Alpha')]);
            // A discovery event alone must repaint the chooser.
            await tester.pump();
          }
          expect(find.text('Synthetic Alpha'), findsOneWidget);
          expect(find.text('Loading notes…'), findsNothing);
          await tester.enterText(find.byType(TextField), 'Beta');
          await tester.pump();
          expect(find.text('No matching notes'), findsOneWidget);
          discovery.publish([note('Synthetic Alpha'), note('Synthetic Beta')]);
          await tester.pump();
          expect(find.text('Synthetic Beta'), findsOneWidget);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Beta',
          );
          expect(
            discovery.requests,
            1,
            reason:
                'Opening or updating the chooser must not start another scan.',
          );
          await tester.enterText(find.byType(TextField), '');
          discovery.publish([]);
          await tester.pump();
          expect(find.text('No notes yet'), findsOneWidget);
          discovery.failures.add(
            DiscoveryFailureEvent(
              const OperationResult.failure(
                OperationOutcome.ioFailure,
                'Synthetic discovery failure',
              ),
              request: discovery.desired,
            ),
          );
          await tester.pump();
          expect(find.text('Notes are unavailable.'), findsOneWidget);
          await tester.tap(find.text('Retry'));
          await tester.pump();
          expect(discovery.requests, 2);
          expect(find.text('Loading notes…'), findsOneWidget);
          discovery.publish([note('Synthetic Retry')]);
          await tester.pump();
          expect(find.text('Synthetic Retry'), findsOneWidget);
          expect(files.writeAttempts, 0);
          await tester.pumpWidget(const SizedBox.shrink());
          discovery.publish([note('After chooser closed')]);
          await tester.pump();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          jobs.dispose();
          await jobs.close();
          model.dispose();
          settings.themeModeNotifier.dispose();
          await tester.runAsync(h.dispose);
        }
      },
    );
  }
  testWidgets('unavailable shared source keeps error and cancel accessible', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    final jobs = SharedAttachmentJobs(
      model: h.editor,
      files: UnusedProviderFiles(),
      settings: h.settings,
      inbox: IncomingShareInbox(
        channel: const MethodChannel('validation/missing-share'),
      ),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingShareScreen(
            batch: IncomingSharedBatch(
              'missing',
              [],
              'Shared files are no longer available.',
            ),
            jobs: jobs,
            model: h.editor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No files available'), findsOneWidget);
      expect(
        find.text('Shared files are no longer available.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Cancel sharing'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
      await jobs.close();
      await tester.runAsync(h.dispose);
    }
  });
  testWidgets('share chooser stays usable with keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = await EditorHarness.create();
    final jobs = SharedAttachmentJobs(
      model: h.editor,
      files: UnusedProviderFiles(),
      settings: h.settings,
      inbox: IncomingShareInbox(
        channel: const MethodChannel('validation/layout'),
      ),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 240),
            ),
            child: child!,
          ),
          home: IncomingShareScreen(
            batch: IncomingSharedBatch('synthetic', [
              {'name': 'Synthetic filename 音声.fnote', 'length': 128},
            ], null),
            jobs: jobs,
            model: h.editor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared files'), findsOneWidget);
      expect(find.text('Attach and open editor'), findsNothing);
      expect(find.text('Attach in background'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      await tester.ensureVisible(find.text('Open note after attaching'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open note after attaching'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.ensureVisible(find.text('Validate and Import'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
      await jobs.close();
      await tester.runAsync(h.dispose);
    }
  });
  test(
    'failed package adoption closes its claimed lease and refreshes pending files',
    () async {
      final h = await EditorHarness.create();
      final files = ImportProviderFiles()..reject = true;
      const channel = MethodChannel('validation/rejected-package');
      const documents = MethodChannel('future_notes/documents');
      final closed = <String>[];
      final source = <Object?, Object?>{
        'name': 'note.fnote',
        'length': 12,
        'path': '/synthetic/fd',
        'lease': 'owned',
        'identity': 'content://synthetic',
      };
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'claim' ? source : [],
      );
      messenger.setMockMethodCallHandler(documents, (call) async {
        closed.add(call.method);
        return null;
      });
      final jobs = SharedAttachmentJobs(
        model: h.editor,
        files: files,
        settings: h.settings,
        inbox: IncomingShareInbox(channel: channel),
      );
      try {
        await expectLater(
          jobs.takePackage(
            IncomingSharedBatch('batch', [source], null),
            source,
          ),
          throwsStateError,
        );
        expect(closed, ['forgetPickedSource', 'closePickedSource']);
        expect(jobs.batches.value, isEmpty);
        expect(jobs.jobs.value, isEmpty);
      } finally {
        jobs.dispose();
        await jobs.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(documents, null);
        await h.dispose();
      }
    },
  );
  for (final names in [
    <String>['Travel.FNOTE'],
    <String>['a.fnote', 'b.fnote', 'photo.jpg'],
    <String>['archive.fnote.exe', 'photo.jpg'],
  ]) {
    testWidgets('shared package import choice is metadata-only for $names', (
      tester,
    ) async {
      final h = await EditorHarness.create();
      final jobs = SharedAttachmentJobs(
        model: h.editor,
        files: UnusedProviderFiles(),
        settings: h.settings,
        inbox: IncomingShareInbox(
          channel: const MethodChannel('validation/package-choice'),
        ),
      );
      IncomingShareResult? result;
      final before = Map.of(h.files.contents);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<IncomingShareResult>(
                        MaterialPageRoute(
                          builder: (_) => IncomingShareScreen(
                            batch: IncomingSharedBatch('batch', [
                              for (var i = 0; i < names.length; i++)
                                {
                                  'name': names[i],
                                  'length': 32,
                                  'lease': 'lease-$i',
                                },
                            ], null),
                            jobs: jobs,
                            model: h.editor,
                          ),
                        ),
                      );
                },
                child: const Text('Receive'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Receive'));
        await tester.pumpAndSettle();
        final packages = names
            .where((n) => n.toLowerCase().endsWith('.fnote'))
            .toList();
        if (packages.isEmpty) {
          expect(find.text('Validate and Import'), findsNothing);
          await tester.tap(find.byTooltip('Cancel sharing'));
        } else {
          expect(
            tester
                .widget<TextButton>(
                  find.ancestor(
                    of: find.text('Validate and Import'),
                    matching: find.byType(TextButton),
                  ),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.text('Validate and Import'));
          await tester.pumpAndSettle();
          if (packages.length > 1) {
            expect(find.text('Choose note package'), findsOneWidget);
            expect(find.text('photo.jpg'), findsNothing);
            await tester.tap(find.text(packages.last));
          }
        }
        await tester.pumpAndSettle();
        expect(
          result?.importSource?['name'],
          packages.isEmpty ? null : packages.last,
        );
        expect(result?.target, isNull);
        expect(h.files.contents, before);
        expect(jobs.jobs.value, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        jobs.dispose();
        await jobs.close();
        await tester.runAsync(h.dispose);
      }
    });
  }
  test(
    'claiming one package preserves the other pending source without payload reads',
    () async {
      final h = await EditorHarness.create();
      final files = ImportProviderFiles();
      const channel = MethodChannel('validation/package-claim');
      final sources = <Map<Object?, Object?>>[
        {
          'name': 'a.fnote',
          'length': 64,
          'path': '/synthetic/owned-fd',
          'lease': 'package',
        },
        {
          'name': 'other.pdf',
          'length': 12,
          'path': '/synthetic/other-fd',
          'lease': 'other',
        },
      ];
      final batch = IncomingSharedBatch('receipt', List.of(sources), null);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'claim') {
              expect(call.arguments, {'id': 'receipt', 'lease': 'package'});
              return sources.removeAt(0);
            }
            if (call.method == 'pending')
              return [
                {'id': 'receipt', 'sources': sources},
              ];
            throw StateError('Unexpected payload or batch-wide operation');
          });
      final jobs = SharedAttachmentJobs(
        model: h.editor,
        files: files,
        settings: h.settings,
        inbox: IncomingShareInbox(channel: channel),
      );
      try {
        final file = await jobs.takePackage(batch, batch.sources.first);
        expect(file.name, 'a.fnote');
        expect(files.adopted, ['package']);
        expect(jobs.batches.value.single.sources.single['lease'], 'other');
        expect(calls, ['claim', 'pending']);
        expect(jobs.jobs.value, isEmpty);
      } finally {
        jobs.dispose();
        await jobs.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await h.dispose();
      }
    },
  );
  testWidgets('closing share chooser leaves draft and library untouched', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    final inbox = IncomingShareInbox(
      channel: const MethodChannel('validation/incoming-shares'),
    );
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(inbox.channel, (call) async {
          calls.add(call.method);
          return null;
        });
    final jobs = SharedAttachmentJobs(
      model: h.editor,
      files: UnusedProviderFiles(),
      settings: h.settings,
      inbox: inbox,
    );
    try {
      h.editor.quillController.document.insert(0, 'Keep unpublished draft');
      final before = h.editor.quillController.document.toDelta().toJson();
      final filesBefore = Map.of(h.files.contents);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => IncomingShareScreen(
                      batch: IncomingSharedBatch('synthetic', [
                        {'name': 'synthetic.txt', 'length': 12},
                      ], null),
                      jobs: jobs,
                      model: h.editor,
                    ),
                  ),
                ),
                child: const Text('Receive'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Receive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel sharing'));
      await tester.pumpAndSettle();
      expect(find.text('Receive'), findsOneWidget);
      expect(h.editor.quillController.document.toDelta().toJson(), before);
      expect(h.files.contents, filesBefore);
      expect(jobs.jobs.value, isEmpty);
      expect(calls, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
      await jobs.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(inbox.channel, null);
      await tester.runAsync(h.dispose);
    }
  });
  for (final queuedSave in [false, true]) {
    test(
      'background publication preserves editing and queuedSave=$queuedSave',
      () async {
        final h = await EditorHarness.create();
        final files = ShareFiles(h.files.libraryRoot);
        final model = ContentViewModel(
          fileService: files,
          settings: h.settings,
          encryptionService: h.encryption,
          startBackgroundServices: false,
        );
        try {
          final target = await model.createSharedNote('Synthetic target', null);
          expect(model.currentContentPath, isNull);
          expect(
            (await model.loadNote(target.reference.fileName)).isSuccess,
            true,
          );
          model.quillController.document.insert(0, 'Unpublished draft');
          model.quillController.updateSelection(
            const TextSelection.collapsed(offset: 5),
            ChangeSource.local,
          );
          final beforeDelta = model.quillController.document.toDelta().toJson();
          final pause = PausePoint();
          files.readPauses[target.reference.fileName] = pause;
          final completed = model.commitSharedAttachment(
            target,
            AttachmentModel(
              id: 'shared-a',
              fileName: 'report with spaces.pdf',
              size: 12,
            ),
            const PreparedAttachmentFile(
              'shared-a',
              StreamingFileSource('/synthetic/must-not-read', 16),
            ),
            cancelled: () => false,
          );
          await pause.started.future;
          final saving = queuedSave ? model.saveNote() : null;
          pause.resume();
          await completed;
          if (saving != null) expect((await saving).isSuccess, true);
          expect(
            model.quillController.document.toDelta().toJson(),
            beforeDelta,
          );
          expect(model.quillController.selection.baseOffset, 5);
          expect(model.attachments.map((a) => a.id), contains('shared-a'));
          expect(model.draftSession.isDirty, !queuedSave);
          final encoded = files.contents[model.currentContentPath]!;
          final stored =
              jsonDecode((await h.encryption.decryptAppResult(encoded)).value!)
                  as Map;
          expect((stored['attachments'] as List).single['id'], 'shared-a');
          if (queuedSave)
            expect(stored['content'], contains('Unpublished draft'));
          else
            expect(stored['content'], isNot(contains('Unpublished draft')));
        } finally {
          model.dispose();
          await model.closeLibraryResources();
          await h.dispose();
        }
      },
    );
  }
  test(
    'background target stays independent of navigation and credentials are revocable',
    () async {
      final h = await EditorHarness.create();
      final files = ShareFiles(h.files.libraryRoot);
      final model = ContentViewModel(
        fileService: files,
        settings: h.settings,
        encryptionService: h.encryption,
        startBackgroundServices: false,
      );
      try {
        final first = await model.createSharedNote(
          'Protected',
          'synthetic-password',
        );
        final second = await model.createSharedNote('Other', null);
        expect(
          (await model.prepareSharedTarget(first.reference.fileName)).password,
          'synthetic-password',
        );
        expect(
          (await model.loadNote(second.reference.fileName)).isSuccess,
          true,
        );
        model.quillController.document.insert(0, 'Other note unsaved');
        final body = model.quillController.document.toDelta().toJson();
        await model.commitSharedAttachment(
          first,
          AttachmentModel(id: 'bg', fileName: 'same.bin'),
          const PreparedAttachmentFile(
            'bg',
            StreamingFileSource('/not-read', 16),
          ),
          cancelled: () => false,
        );
        expect(model.currentContentPath, second.reference.contentPath);
        expect(model.quillController.document.toDelta().toJson(), body);
        expect(model.draftSession.isDirty, true);
        expect((await model.saveNote()).isSuccess, true);
        expect(
          (await model.loadNote(first.reference.fileName)).isSuccess,
          true,
        );
        expect((await model.manualLock()).isSuccess, true);
        expect(model.sharedTargetCredentialCurrent(first), false);
        await expectLater(
          model.commitSharedAttachment(
            first,
            AttachmentModel(id: 'revoked', fileName: 'revoked.bin'),
            const PreparedAttachmentFile(
              'revoked',
              StreamingFileSource('/not-read', 16),
            ),
            cancelled: () => false,
          ),
          throwsA(isA<FileJobCancelled>()),
        );
      } finally {
        model.dispose();
        await model.closeLibraryResources();
        await h.dispose();
      }
    },
  );
  test(
    'locked target requires a valid password without changing the editor',
    () async {
      final h = await EditorHarness.create();
      final files = ShareFiles(h.files.libraryRoot);
      final model = ContentViewModel(
        fileService: files,
        settings: h.settings,
        encryptionService: h.encryption,
        startBackgroundServices: false,
      );
      try {
        final metadata = NoteModel(
          id: 'protected',
          title: 'Protected',
          timestamp: 1700000000000,
          isLocked: true,
          content: await h.encryption.encrypt(
            '[{"insert":"secret\\n"}]',
            password: 'correct',
          ),
        );
        final ref = await files.newNoteReference('protected');
        await files.writeResolved(
          ref,
          await h.encryption.encryptApp(jsonEncode(metadata.toJson())),
        );
        model.quillController.document.insert(0, 'Keep this draft');
        expect(
          () => model.prepareSharedTarget(ref.fileName),
          throwsA(isA<SharedAttachmentPasswordRequired>()),
        );
        expect(
          () => model.prepareSharedTarget(ref.fileName, password: 'wrong'),
          throwsA(isA<SharedAttachmentPasswordRequired>()),
        );
        final target = await model.prepareSharedTarget(
          ref.fileName,
          password: 'correct',
        );
        expect(target.password, 'correct');
        expect(model.currentContentPath, isNull);
        expect(
          model.quillController.document.toPlainText(),
          contains('Keep this draft'),
        );
      } finally {
        model.dispose();
        await model.closeLibraryResources();
        await h.dispose();
      }
    },
  );
  testWidgets(
    'background task aggregation cancels the correct owner and clears native activity',
    (tester) async {
      final h = await EditorHarness.create();
      const channel = MethodChannel('future_notes/jobs');
      final updates = <List>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'interruptedJobs') return '[]';
            if (call.method == 'update')
              updates.add(call.arguments['jobs'] as List);
            return null;
          });
      final extra = ExtraJobs();
      final state = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'shared',
          owner: -1,
          fileName: 'Synthetic shared file',
          phase: AttachmentJobPhase.encrypting,
          total: 100,
          bytes: 10,
        ),
      );
      extra.jobs.value = [state];
      final binding = MobileJobBinding(h.editor, additional: extra);
      await binding.interrupted;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BackgroundTasksDialog(model: h.editor, jobs: binding),
            ),
          ),
        );
        expect(binding.activeCount.value, 1);
        await tester.tap(find.byTooltip('Cancel this job'));
        expect(extra.cancelled, ['shared']);
        state.update(
          const AttachmentJobSnapshot(
            id: 'shared',
            owner: -1,
            fileName: 'Synthetic shared file',
            phase: AttachmentJobPhase.cancelled,
          ),
        );
        await tester.pumpAndSettle();
        expect(binding.activeCount.value, 0);
        expect(updates.last, isEmpty);
        expect(find.textContaining('Cancelled'), findsOneWidget);
        expect(h.files.writes, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        binding.dispose();
        state.dispose();
        extra.jobs.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.runAsync(h.dispose);
      }
    },
  );
  test(
    'incoming inbox acknowledges only receipt identity and preserves duplicate filenames',
    () async {
      const channel = MethodChannel('synthetic/incoming');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'pending')
              return [
                {
                  'id': 'batch',
                  'sources': [
                    {'lease': 'a', 'name': 'same.txt', 'length': 2},
                    {'lease': 'b', 'name': 'same.txt', 'length': 3},
                  ],
                },
              ];
            return null;
          });
      final inbox = IncomingShareInbox(channel: channel);
      try {
        final batch = (await inbox.pending()).single;
        expect(batch.sources.length, 2);
        await inbox.discard(batch.id);
        expect(calls.last.arguments, {'id': 'batch'});
        expect(calls.any((c) => c.method.contains('read')), false);
      } finally {
        inbox.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
}
