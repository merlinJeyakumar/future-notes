import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_thumbnails.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_strip.dart';
import 'support/editor_harness.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'attachment_strip_test.dart' show FakeOpenCache;

AttachmentModel media(String id, [String ext = 'mp4']) =>
    AttachmentModel(id: id, fileName: '$id.$ext', encryptedThumbnail: 'v1:$id');
Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'explicit refresh retries failed restore without progress retry loops',
    () async {
      var calls = 0;
      final thumbnails = MobileAttachmentThumbnails(
        enabled: true,
        restore: (_) async {
          calls++;
          return calls == 1 ? null : Uint8List.fromList([1]);
        },
      );
      thumbnails.update(owner: 1, attachments: [media('a')], unlocked: true);
      await settle();
      thumbnails.update(owner: 1, attachments: [media('a')], unlocked: true);
      await settle();
      expect(calls, 1);
      thumbnails.update(
        owner: 1,
        attachments: [media('a')],
        unlocked: true,
        refreshRevision: 1,
      );
      await settle();
      expect(thumbnails.image('a'), [1]);
      thumbnails.reportDecodeFailure('a', thumbnails.image('a')!);
      await settle();
      expect(thumbnails.image('a'), isNull);
      thumbnails.update(
        owner: 1,
        attachments: [media('a')],
        unlocked: true,
        refreshRevision: 2,
      );
      await settle();
      expect(calls, 3);
      thumbnails.dispose();
    },
  );
  testWidgets(
    'unlock restores metadata in collapsed dock without payload preparation; gallery shares it and lock removes it',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      h.seed(
        'protected',
        h.note(
          'protected',
          'body',
          locked: true,
          attachments: [
            {
              'id': 'video',
              'fileName': 'Demo.mp4',
              'size': 10,
              'encryptedThumbnail': 'v1:synthetic',
            },
          ],
        ),
      );
      await h.editor.loadNote('protected');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentStrip(
                viewModel: h.editor,
                thumbnailFactory: (prepare) => MobileAttachmentThumbnails(
                  enabled: true,
                  restore: (_) async => png,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(cache.opens, 0);
        expect(await h.editor.unlockNote('synthetic-password'), true);
        await tester.pumpAndSettle();
        final image = find.byKey(const ValueKey('attachment-thumbnail-video'));
        expect(image, findsOneWidget);
        expect(cache.opens, 0);
        await tester.tap(find.byKey(const ValueKey('attachment-show-all')));
        await tester.pumpAndSettle();
        expect(image, findsWidgets);
        expect(cache.opens, 0);
        await h.editor.manualLock();
        await tester.pumpAndSettle();
        expect(image, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets('a previous failed open cannot hide a valid stored thumbnail', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    h.seed(
      'demo',
      h.note(
        'demo',
        'body',
        attachments: [
          {
            'id': 'video',
            'fileName': 'Demo.mp4',
            'encryptedThumbnail': 'v1:synthetic',
          },
        ],
      ),
    );
    await h.editor.loadNote('demo');
    final failure = AttachmentJobState(
      AttachmentJobSnapshot(
        id: 'old-open',
        owner: h.editor.draftSession.generation,
        fileName: 'Demo.mp4',
        phase: AttachmentJobPhase.failed,
        originalAttachmentId: 'video',
        operation: AttachmentJobOperation.open,
      ),
    );
    h.editor.attachmentJobsNotifier.value = [failure];
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentStrip(
              viewModel: h.editor,
              thumbnailFactory: (_) => MobileAttachmentThumbnails(
                enabled: true,
                restore: (_) async => png,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attachment-thumbnail-video')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      failure.dispose();
      h.disposeEditor();
      await tester.runAsync(h.dispose);
    }
  });
  test(
    'unlock restores serially, retains results and defers during other jobs',
    () async {
      final prepared = <String>[];
      final gate = Completer<Uint8List?>();
      final thumbnails = MobileAttachmentThumbnails(
        enabled: true,
        restore: (a) async {
          prepared.add(a.id);
          return a.id == 'a' ? gate.future : Uint8List.fromList([2]);
        },
      );
      final entries = [
        media('a'),
        media('b'),
        AttachmentModel(id: 'plain', fileName: 'plain.txt'),
      ];
      thumbnails.update(
        owner: 1,
        attachments: entries,
        unlocked: true,
        defer: true,
      );
      await settle();
      expect(prepared, isEmpty);
      thumbnails.update(owner: 1, attachments: entries, unlocked: true);
      await settle();
      expect(prepared, ['a']);
      gate.complete(Uint8List.fromList([1]));
      await settle();
      expect(prepared, ['a', 'b']);
      expect(thumbnails.image('a'), isNotNull);
      thumbnails.update(owner: 1, attachments: entries, unlocked: true);
      await settle();
      expect(prepared, ['a', 'b']);
      thumbnails.update(owner: 1, attachments: [], unlocked: false);
      expect(thumbnails.image('a'), isNull);
      thumbnails.dispose();
    },
  );
  test(
    'lock, credential/note changes and removal reject late results',
    () async {
      final pending = <Completer<Uint8List?>>[];
      final thumbnails = MobileAttachmentThumbnails(
        enabled: true,
        restore: (_) {
          final c = Completer<Uint8List?>();
          pending.add(c);
          return c.future;
        },
      );
      thumbnails.update(
        owner: ('note', 1),
        attachments: [media('a')],
        unlocked: true,
      );
      await settle();
      expect(pending.length, 1);
      thumbnails.update(
        owner: ('note', 2),
        attachments: [media('a')],
        unlocked: true,
      );
      pending[0].complete(Uint8List.fromList([1]));
      await settle();
      expect(thumbnails.image('a'), isNull);
      expect(pending.length, 2);
      thumbnails.update(owner: ('note', 2), attachments: [], unlocked: false);
      pending[1].complete(Uint8List.fromList([2]));
      await settle();
      expect(thumbnails.image('a'), isNull);
      thumbnails.update(
        owner: ('other', 1),
        attachments: [media('b')],
        unlocked: true,
      );
      await settle();
      thumbnails.update(owner: ('other', 1), attachments: [], unlocked: true);
      pending[2].complete(Uint8List.fromList([3]));
      await settle();
      expect(thumbnails.image('b'), isNull);
      thumbnails.dispose();
    },
  );
  test(
    'unsupported frames keep fallback icons without retry loops; disabled platforms do no work',
    () async {
      var calls = 0;
      final thumbnails = MobileAttachmentThumbnails(
        enabled: true,
        restore: (_) async {
          calls++;
          return null;
        },
      );
      for (var i = 0; i < 3; i++) {
        thumbnails.update(owner: 1, attachments: [media('a')], unlocked: true);
        await settle();
      }
      expect(calls, 1);
      expect(thumbnails.image('a'), isNull);
      thumbnails.dispose();
      final disabled = MobileAttachmentThumbnails(
        enabled: false,
        restore: (_) async {
          calls++;
          return null;
        },
      );
      disabled.update(owner: 1, attachments: [media('b')], unlocked: true);
      await settle();
      expect(calls, 1);
      disabled.dispose();
    },
  );
  test(
    'legacy metadata never calls restore and refreshed ciphertext replaces same ID',
    () async {
      var calls = 0;
      final thumbnails = MobileAttachmentThumbnails(
        enabled: true,
        restore: (a) async {
          calls++;
          return Uint8List.fromList([calls]);
        },
      );
      thumbnails.update(
        owner: 1,
        attachments: [AttachmentModel(id: 'a', fileName: 'a.mp4')],
        unlocked: true,
      );
      await settle();
      expect(calls, 0);
      thumbnails.update(owner: 1, attachments: [media('a')], unlocked: true);
      await settle();
      expect(thumbnails.image('a'), [1]);
      thumbnails.update(
        owner: 1,
        attachments: [
          AttachmentModel(
            id: 'a',
            fileName: 'a.mp4',
            encryptedThumbnail: 'v1:replacement',
          ),
        ],
        unlocked: true,
      );
      await settle();
      expect(thumbnails.image('a'), [2]);
      thumbnails.dispose();
    },
  );
}
