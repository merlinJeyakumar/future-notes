import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/windows_desktop_actions.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_strip.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'support/editor_harness.dart';

class FakeOpenCache extends AttachmentOpenCache {
  FakeOpenCache()
    : super(
        rootResolver: () async => throw StateError('No real cache'),
        sourceResolver: (_, id) async => throw StateError('No real data'),
      );
  int opens = 0;
  int invalidations = 0;
  CachedAttachmentFile? file;
  Completer<OperationResult<CachedAttachmentFile>>? gate;
  @override
  Future<void> initialize() async {}
  @override
  Future<OperationResult<CachedAttachmentFile>> prepare(
    NoteReference reference,
    AttachmentModel attachment,
    int credentialGeneration, {
    String? password,
    dynamic onProgress,
  }) async {
    opens++;
    if (gate != null) return gate!.future;
    file = const CachedAttachmentFile(
      'D:/synthetic-cache/demo.mp4',
      9 * 1024 * 1024,
      'synthetic',
    );
    return OperationResult.success(file);
  }

  @override
  CachedAttachmentFile? peek(
    NoteReference reference,
    String id,
    int credentials,
  ) => file;
  @override
  Future<CacheCleanupResult> invalidateNote(NoteReference reference) async {
    invalidations++;
    file = null;
    return const CacheCleanupResult(0);
  }

  @override
  Future<CacheCleanupResult> close() async {
    file = null;
    return const CacheCleanupResult(0);
  }
}

class FakePlayer implements AttachmentMediaPlayer {
  int disposed = 0;
  int paused = 0;
  @override
  Widget build(BuildContext context) => const Text('Synthetic embedded video');
  @override
  Future<void> dispose() async {
    disposed = 1;
  }

  @override
  Future<void> pause() async {
    paused++;
  }
}

class FakeDesktop implements DesktopActions {
  final controller = StreamController<String>.broadcast();
  final opened = <String>[];
  int hides = 0;
  bool failHide = false;
  @override
  Stream<String> get events => controller.stream;
  @override
  Future<String> cacheRoot({String? validationRoot}) async =>
      throw StateError('Test must not resolve native cache');
  @override
  Future<OperationResult<void>> minimizeToTray() async {
    hides++;
    return failHide
        ? const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Synthetic tray failure',
          )
        : const OperationResult.success();
  }

  @override
  Future<OperationResult<void>> openFile(String path) async {
    opened.add(path);
    return const OperationResult.success();
  }

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}

void main() {
  testWidgets(
    'repeated cached Open retires terminal job notifiers after the frame',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            {'id': 'video', 'fileName': 'video.avi', 'size': 1024},
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AttachmentStrip(viewModel: h.editor)),
          ),
        );
        await h.editor.openAttachment(h.editor.attachments.single);
        final first = h.editor.attachmentJobsNotifier.value.single;
        for (var i = 0; i < 24; i++) {
          await h.editor.openAttachment(h.editor.attachments.single);
        }
        expect(h.editor.attachmentJobsNotifier.value.length, 1);
        await tester.pump();
        expect(() => first.progress.addListener(() {}), throwsFlutterError);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'image preview uses bounded decode dimensions and evicts on close',
    (tester) async {
      final h = await EditorHarness.create();
      final file = File('${h.run.path}/synthetic.png');
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      file.writeAsBytesSync(bytes);
      final attachment = AttachmentModel(
        id: 'image',
        fileName: 'synthetic.png',
        size: bytes.length,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentViewer(
                viewModel: h.editor,
                attachment: attachment,
                file: CachedAttachmentFile(
                  file.path,
                  bytes.length,
                  'synthetic',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final provider =
            tester.widget<Image>(find.byType(Image)).image as ResizeImage;
        expect(provider.width, inInclusiveRange(1, 2048));
        expect(provider.height, inInclusiveRange(1, 2048));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(file.readAsBytesSync(), bytes);
        await tester.runAsync(() async {
          await provider.evict();
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'row never decrypts during rendering; click opens file-backed player; More opens system app',
    (tester) async {
      final cache = FakeOpenCache();
      final desktop = FakeDesktop();
      final player = FakePlayer();
      final harness = await EditorHarness.create(
        attachmentOpenCache: cache,
        desktopActions: desktop,
      );
      harness.seed(
        'synthetic',
        harness.note(
          'synthetic',
          'body',
          attachments: [
            {
              'id': 'video',
              'fileName': 'demo-video.mp4',
              'size': 9 * 1024 * 1024,
            },
          ],
        ),
      );
      await harness.editor.loadNote('synthetic');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentStrip(
                viewModel: harness.editor,
                playerFactory: (_) => player,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(cache.opens, 0);
        expect(harness.encryption.binaryDecryptCalls, 0);
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        await tester.tap(find.text('Open'));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(cache.opens, 1);
        expect(find.text('Synthetic embedded video'), findsOneWidget);
        expect(find.byType(AttachmentViewer), findsOneWidget);
        await harness.editor.pauseAttachmentViewers();
        expect(player.paused, 1);
        expect(player.disposed, 0);
        await tester.tap(find.byType(AttachmentMoreButton).last);
        await tester.pumpAndSettle();
        expect(
          find.text('Open in Future Notes (Already open)'),
          findsOneWidget,
        );
        expect(find.text('Save As'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        await tester.tap(find.text('Open in system app'));
        await tester.pumpAndSettle();
        expect(desktop.opened, ['D:/synthetic-cache/demo.mp4']);
        await harness.editor.closeAttachmentCache();
        await tester.pumpAndSettle();
        expect(player.disposed, 1);
        expect(find.text('Synthetic embedded video'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await desktop.dispose();
        await tester.runAsync(harness.dispose);
      }
    },
  );
  testWidgets(
    'pending first attachment has inline phases, More and cancellation without a dialog',
    (tester) async {
      final harness = await EditorHarness.create();
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'synthetic',
          owner: 0,
          fileName: 'demo-video.mp4',
          phase: AttachmentJobPhase.encrypting,
          bytes: 4,
          total: 10,
        ),
      );
      harness.editor.attachmentJobsNotifier.value = [job];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AttachmentStrip(viewModel: harness.editor)),
          ),
        );
        expect(find.text('Encrypting'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        job.update(
          const AttachmentJobSnapshot(
            id: 'synthetic',
            owner: 0,
            fileName: 'demo-video.mp4',
            phase: AttachmentJobPhase.finalizing,
          ),
        );
        await tester.pump();
        expect(find.text('Finishing safely…'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        job.update(
          const AttachmentJobSnapshot(
            id: 'synthetic',
            owner: 0,
            fileName: 'demo-video.mp4',
            phase: AttachmentJobPhase.completed,
          ),
        );
        harness.editor.attachmentsNotifier.value = [
          AttachmentModel(id: 'synthetic', fileName: 'demo-video.mp4'),
        ];
        await tester.pump();
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Finishing safely…'), findsNothing);
        harness.editor.isLockedNotifier.value = true;
        await tester.pump();
        expect(find.byType(AttachmentMoreButton), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        job.dispose();
        await tester.runAsync(harness.dispose);
      }
    },
  );
}
