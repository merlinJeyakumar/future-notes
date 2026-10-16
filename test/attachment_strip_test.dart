import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/services.dart';
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
  int played = 0;
  @override
  Future<void> play() async {
    played++;
  }

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
    'dock stays left aligned in the editor and Show all searches every filename',
    (tester) async {
      final cache = FakeOpenCache();
      final desktop = FakeDesktop();
      final h = await EditorHarness.create(
        attachmentOpenCache: cache,
        desktopActions: desktop,
      );
      final names = [
        'Project overview.pdf',
        'Budget 2026.xlsx',
        'Notes.docx',
        'Demo video.mp4',
        'Summary.pdf',
        'Photo.png',
      ];
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            for (var i = 0; i < names.length; i++)
              {'id': 'item$i', 'fileName': names[i], 'size': 1024},
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  AttachmentStrip(viewModel: h.editor),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(AttachmentStrip)).left, 0);
        expect(
          tester.getRect(find.byType(AttachmentStrip)).width,
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
        );
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('attachment-open-item0')))
              .dx,
          16,
        );
        expect(
          tester.getTopLeft(find.text('Show all')).dx,
          lessThan(tester.getTopLeft(find.text('Attachments (6)')).dx),
        );
        await tester.tap(find.text('Show all'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        final search = find.byKey(const ValueKey('attachment-filename-search'));
        expect(find.text('All attachments'), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          true,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.byType(AttachmentMoreButton),
          ),
          findsNWidgets(6),
        );
        await tester.enterText(search, '  BuDgEt ');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: dialog,
            matching: find.byType(AttachmentMoreButton),
          ),
          findsOneWidget,
        );
        expect(find.text('Budget 2026.xlsx'), findsOneWidget);
        expect(find.text('Notes.docx'), findsNothing);
        await tester.enterText(search, 'not-present');
        await tester.pumpAndSettle();
        expect(find.text('No matching attachments'), findsOneWidget);
        expect(cache.opens, 0);
        await tester.tap(find.byTooltip('Clear attachment search'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: dialog,
            matching: find.byType(AttachmentMoreButton),
          ),
          findsNWidgets(6),
        );
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          true,
        );
        await tester.enterText(search, 'notes.docx');
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: dialog,
            matching: find.byTooltip('More actions for Notes.docx'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open in system app'));
        await tester.pumpAndSettle();
        expect(cache.opens, 1);
        expect(desktop.opened, ['D:/synthetic-cache/demo.mp4']);
        h.editor.isLockedNotifier.value = true;
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(find.text('Show all'), findsNothing);
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await desktop.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets(
    'opening switching and unlocking collapse the dock; ordinary updates retain expansion',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      for (final id in ['first', 'second', 'protected']) {
        h.seed(
          id,
          h.note(
            id,
            'body',
            locked: id == 'protected',
            attachments: [
              {'id': id, 'fileName': '$id.txt', 'size': 10},
            ],
          ),
        );
      }
      await h.editor.loadNote('first');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AttachmentStrip(viewModel: h.editor)),
          ),
        );
        final dock = find.byKey(const ValueKey('attachment-dock-items'));
        expect(tester.getSize(dock).height, 36);
        await tester.tap(find.text('Attachments (1)'));
        await tester.pump();
        expect(tester.getSize(dock).height, 104);
        h.editor.titleController.text = 'Edited synthetic title';
        h.editor.attachmentCacheNotifier.value++;
        await tester.pump();
        expect(tester.getSize(dock).height, 104);
        expect((await h.editor.saveNote()).isSuccess, isTrue);
        await tester.pump();
        expect(tester.getSize(dock).height, 104);
        await h.editor.loadNote('second');
        await tester.pump();
        expect(tester.getSize(dock).height, 36);
        await tester.tap(find.text('Attachments (1)'));
        await tester.pump();
        expect(tester.getSize(dock).height, 104);
        await h.editor.loadNote('protected');
        await tester.pump();
        expect(dock, findsNothing);
        expect(await h.editor.unlockNote('synthetic-password'), isTrue);
        await tester.pump();
        expect(tester.getSize(dock).height, 36);
        expect(cache.opens, 0);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets('collapsed icons keep hover Open keyboard and More actions', (
    tester,
  ) async {
    final cache = FakeOpenCache();
    final player = FakePlayer();
    final desktop = FakeDesktop();
    final h = await EditorHarness.create(
      attachmentOpenCache: cache,
      desktopActions: desktop,
    );
    const name = 'Synthetic complete recording filename.mp4';
    h.seed(
      'synthetic',
      h.note(
        'synthetic',
        'body',
        attachments: [
          {'id': 'video', 'fileName': name, 'size': 1024},
        ],
      ),
    );
    await h.editor.loadNote('synthetic');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentStrip(
              viewModel: h.editor,
              playerFactory: (_) => player,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('attachment-open-video'));
      expect(tester.getSize(card), const Size(56, 36));
      expect(find.text(name), findsNothing);
      expect(find.text('video · 1.0 KiB'), findsNothing);
      final iconPoint = tester.getRect(card).centerLeft + const Offset(12, 0);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(iconPoint);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(name), findsOneWidget);
      expect(cache.opens, 0);
      await mouse.moveTo(const Offset(790, 590));
      await tester.pumpAndSettle();
      await tester.tapAt(iconPoint);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic embedded video'), findsOneWidget);
      expect(cache.opens, 1);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      tester.widget<InkWell>(card).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic embedded video'), findsOneWidget);
      expect(cache.opens, 2);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions for $name'));
      await tester.pumpAndSettle();
      expect(cache.opens, 2);
      expect(find.text('Save As'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      await tester.tap(find.text('Open in system app'));
      await tester.pumpAndSettle();
      expect(cache.opens, 3);
      expect(desktop.opened, ['D:/synthetic-cache/demo.mp4']);
      expect(h.files.writeAttempts, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      h.disposeEditor();
      await tester.pump(const Duration(seconds: 3));
      await desktop.dispose();
      await tester.runAsync(h.dispose);
    }
  });

  for (final collapsed in [false, true]) {
    testWidgets(
      'Open keeps all four ${collapsed ? 'collapsed' : 'expanded'} cards fixed through progress and failure',
      (tester) async {
        final cache = FakeOpenCache()
          ..gate = Completer<OperationResult<CachedAttachmentFile>>();
        final h = await EditorHarness.create(attachmentOpenCache: cache);
        h.seed(
          'synthetic',
          h.note(
            'synthetic',
            'body',
            attachments: [
              for (var i = 0; i < 4; i++)
                {
                  'id': 'video$i',
                  'fileName': 'Synthetic long recording filename $i.mp4',
                  'size': 1024,
                },
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
          if (!collapsed) {
            await tester.tap(find.text('Attachments (4)'));
          }
          await tester.pumpAndSettle();
          final dock = find.byKey(const ValueKey('attachment-dock-items'));
          final bounds = tester.getRect(dock);
          final cards = [
            for (var i = 0; i < 4; i++)
              find.byKey(ValueKey('attachment-open-video$i')),
          ];
          final cardBounds = cards.map(tester.getRect).toList();
          await tester.tap(cards.first);
          await tester.pump();
          final job = h.editor.attachmentJobsNotifier.value.single;
          final initial = job.progress.value;
          for (final phase in [
            AttachmentJobPhase.queued,
            AttachmentJobPhase.preparing,
            AttachmentJobPhase.decrypting,
            AttachmentJobPhase.encrypting,
            AttachmentJobPhase.verifying,
            AttachmentJobPhase.finalizing,
            AttachmentJobPhase.cancelling,
            AttachmentJobPhase.completed,
            AttachmentJobPhase.failed,
          ]) {
            job.update(
              AttachmentJobSnapshot(
                id: initial.id,
                owner: initial.owner,
                fileName: initial.fileName,
                originalAttachmentId: initial.originalAttachmentId,
                operation: initial.operation,
                phase: phase,
                bytes: 4,
                total: 10,
                error: phase == AttachmentJobPhase.failed
                    ? 'Synthetic preparation failure'
                    : null,
              ),
            );
            await tester.pump();
            expect(tester.getRect(dock), bounds, reason: phase.name);
            for (var i = 0; i < cards.length; i++) {
              expect(
                tester.getRect(cards[i]),
                cardBounds[i],
                reason: phase.name,
              );
            }
            expect(
              find.byTooltip('Cancel attachment'),
              job.progress.value.cancellable ? findsOneWidget : findsNothing,
            );
            expect(
              find.descendant(
                of: cards.first,
                matching: find.byIcon(Icons.play_circle_outline),
              ),
              job.progress.value.active ||
                      (collapsed && phase == AttachmentJobPhase.failed)
                  ? findsNothing
                  : findsOneWidget,
            );
            expect(
              find.descendant(
                of: cards.first,
                matching: find.byType(AttachmentMoreButton),
              ),
              job.progress.value.active ? findsNothing : findsOneWidget,
            );
            expect(
              find.byType(AttachmentMoreButton),
              findsNWidgets(job.progress.value.active ? 3 : 4),
            );
            if (phase == AttachmentJobPhase.decrypting) {
              if (collapsed) {
                expect(find.text('Decrypting'), findsNothing);
                expect(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is Tooltip &&
                        widget.message!.contains('Decrypting'),
                  ),
                  findsOneWidget,
                );
              } else {
                expect(find.text('Decrypting'), findsOneWidget);
              }
              expect(
                tester
                    .widget<LinearProgressIndicator>(
                      find.byType(LinearProgressIndicator),
                    )
                    .value,
                .4,
              );
            }
            expect(find.byType(Dialog), findsNothing);
            expect(tester.takeException(), isNull);
          }
          cache.gate!.complete(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Synthetic preparation failure',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(dock), bounds);
          expect(cache.opens, 1);
          expect(h.files.writeAttempts, 0);
          expect(h.editor.attachments.length, 4);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          h.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(h.dispose);
        }
      },
    );
  }

  testWidgets(
    'Windows card hover shows full name and every card surface opens; More remains independent',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      const name = 'Synthetic complete recording filename.mp4';
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            {'id': 'video', 'fileName': name, 'size': 1024},
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentStrip(
                viewModel: h.editor,
                playerFactory: (_) => FakePlayer(),
              ),
            ),
          ),
        );
        await tester.tap(find.textContaining('Attachments ('));
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('attachment-open-video'));
        await mouse.addPointer(location: const Offset(790, 590));
        // Hover a caption rather than only the thumbnail/filename.
        await mouse.moveTo(tester.getCenter(find.text('video · 1.0 KiB')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(name), findsNWidgets(2));
        expect(cache.opens, 0);
        await mouse.moveTo(const Offset(790, 590));
        await tester.pumpAndSettle();
        for (final surface in ['padding', 'filename', 'caption', 'empty']) {
          final rect = tester.getRect(card);
          final point = switch (surface) {
            'padding' => rect.topLeft + const Offset(5, 5),
            'filename' => tester.getCenter(find.text(name)),
            'caption' => tester.getCenter(find.text('video · 1.0 KiB')),
            _ => rect.bottomLeft + const Offset(10, -5),
          };
          final before = cache.opens;
          await tester.tapAt(point);
          await tester.pumpAndSettle();
          expect(
            cache.opens,
            before + 1,
            reason: '$surface should open the card',
          );
          expect(find.byType(AttachmentViewer), findsOneWidget);
          await tester.tap(find.byTooltip('Close preview'));
          await tester.pumpAndSettle();
        }
        final before = cache.opens;
        await tester.tap(find.byTooltip('More actions for $name'));
        await tester.pumpAndSettle();
        expect(find.text('Open in system app'), findsOneWidget);
        expect(cache.opens, before);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        tester.widget<InkWell>(card).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentViewer), findsOneWidget);
        expect(cache.opens, before + 1);
        expect(h.files.writeAttempts, 0);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'small expanded cards wrap names and caption type size and stored date without decrypting',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      h.files.attachmentDate = DateTime(2026, 10, 15, 14, 30);
      const name = 'Synthetic long recording title with multiple words.mp4';
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            {'id': 'video', 'fileName': name, 'size': 1024 * 1024},
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
        await tester.tap(find.text('Attachments (1)'));
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byType(Card));
        expect(size.width, lessThan(112));
        expect(size.height, lessThan(120));
        final filename = tester.widget<Text>(find.text(name));
        expect(
          filename.style!.fontSize,
          lessThan(
            Theme.of(
              tester.element(find.text(name)),
            ).textTheme.labelMedium!.fontSize!,
          ),
        );
        expect(find.text('video · 1.0 MiB'), findsOneWidget);
        expect(find.text('Stored 15/10 14:30'), findsOneWidget);
        expect(h.files.attachmentDateReads, 1);
        await tester.tap(find.text('Attachments (1)'));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(Card)), const Size(56, 36));
        expect(find.text(name), findsNothing);
        expect(find.byTooltip(name), findsOneWidget);
        expect(find.text('video · 1.0 MiB'), findsNothing);
        expect(find.text('Stored 15/10 14:30'), findsNothing);
        expect(h.files.attachmentDateReads, 1);
        expect(cache.opens, 0);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'stale attachment date cannot cross notes and metadata failure stays readable',
    (tester) async {
      final h = await EditorHarness.create();
      for (final id in ['first', 'second']) {
        h.seed(
          id,
          h.note(
            id,
            'body',
            attachments: [
              {'id': id, 'fileName': '$id.pdf', 'size': 1024},
            ],
          ),
        );
      }
      await h.editor.loadNote('first');
      final gate = Completer<DateTime?>();
      h.files.attachmentDateGate = gate;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AttachmentStrip(viewModel: h.editor)),
          ),
        );
        await tester.pump();
        expect(h.files.attachmentDateReads, 1);
        h.files.attachmentDateGate = null;
        h.files.failAttachmentDate = true;
        await h.editor.loadNote('second');
        gate.complete(DateTime(2026, 10, 15, 14, 30));
        await tester.pumpAndSettle();
        expect(find.text('first.pdf'), findsNothing);
        expect(find.text('Stored 15/10 14:30'), findsNothing);
        await tester.tap(find.text('Attachments (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Date unavailable'), findsOneWidget);
        expect(find.text('document · 1.0 KiB'), findsOneWidget);
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'expanded dock shows every attachment; collapsed overflow keeps remaining actions',
    (tester) async {
      final cache = FakeOpenCache();
      final desktop = FakeDesktop();
      final h = await EditorHarness.create(
        attachmentOpenCache: cache,
        desktopActions: desktop,
      );
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            for (var i = 0; i < 6; i++)
              {'id': 'file$i', 'fileName': 'sample$i.png', 'size': 1024},
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
        await tester.tap(find.textContaining('Attachments ('));
        await tester.pumpAndSettle();
        final dock = find.byKey(const ValueKey('attachment-dock-items'));
        final largeHeight = tester.getSize(dock).height;
        expect(find.byType(AttachmentMoreButton), findsNWidgets(6));
        expect(find.byKey(const ValueKey('attachment-overflow')), findsNothing);
        expect(find.text('sample4.png'), findsOneWidget);
        expect(find.text('sample5.png'), findsOneWidget);
        expect(cache.opens, 0);
        await tester.tap(find.text('Attachments (6)'));
        await tester.pump();
        expect(tester.getSize(dock).height, lessThan(largeHeight));
        expect(find.byType(AttachmentMoreButton), findsNWidgets(4));
        expect(find.text('+2'), findsOneWidget);
        expect(find.text('sample0.png'), findsNothing);
        expect(find.byTooltip('sample0.png'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('attachment-overflow')));
        await tester.pumpAndSettle();
        expect(find.text('More attachments'), findsOneWidget);
        expect(find.text('sample4.png'), findsOneWidget);
        expect(find.text('sample5.png'), findsOneWidget);
        expect(cache.opens, 0);
        await tester.tap(find.byTooltip('More actions for sample5.png'));
        await tester.pumpAndSettle();
        expect(find.text('Save As'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        await tester.tap(find.text('Open in system app'));
        await tester.pumpAndSettle();
        expect(cache.opens, 1);
        expect(desktop.opened, ['D:/synthetic-cache/demo.mp4']);
        h.editor.isLockedNotifier.value = true;
        await tester.pumpAndSettle();
        expect(find.text('More attachments'), findsNothing);
        expect(find.text('sample5.png'), findsNothing);
        expect(find.byType(AttachmentMoreButton), findsNothing);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await desktop.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'expanded attachments wrap and scroll without hiding entries or decrypting',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      h.editor.attachmentsNotifier.value = [
        for (var i = 0; i < 20; i++)
          AttachmentModel(id: 'item$i', fileName: 'sample$i.txt'),
      ];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AttachmentStrip(viewModel: h.editor)),
          ),
        );
        await tester.tap(find.text('Attachments (20)'));
        await tester.pumpAndSettle();
        final dock = find.byKey(const ValueKey('attachment-dock-items'));
        expect(find.byKey(const ValueKey('attachment-overflow')), findsNothing);
        expect(find.byType(AttachmentMoreButton), findsNWidgets(20));
        expect(tester.getSize(dock).height, lessThanOrEqualTo(280));
        final first = find.byKey(const ValueKey('attachment-open-item0'));
        final last = find.byKey(const ValueKey('attachment-open-item19'));
        expect(
          tester.getTopLeft(last).dy,
          greaterThan(tester.getTopLeft(first).dy),
        );
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(last).bottom,
          lessThanOrEqualTo(tester.getRect(dock).bottom + 1),
        );
        expect(tester.takeException(), isNull);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(cache.opens, 0);
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
    'four items need no overflow; compact cached image stays file backed',
    (tester) async {
      final cache = FakeOpenCache();
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      final file = File('${h.run.path}/cached.png');
      file.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
      cache.file = CachedAttachmentFile(
        file.path,
        file.lengthSync(),
        'synthetic',
      );
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            for (var i = 0; i < 4; i++)
              {'id': 'image$i', 'fileName': 'image$i.png'},
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
        await tester.tap(find.textContaining('Attachments ('));
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('attachment-overflow')), findsNothing);
        final image = find.byType(Image).first;
        final big = tester.getSize(image).height;
        final provider = tester.widget<Image>(image).image as ResizeImage;
        expect(provider.width, 320);
        expect(provider.height, 160);
        await tester.tap(find.text('Attachments (4)'));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(Image).first).height, lessThan(big));
        expect(cache.opens, 0);
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
    'narrow scaled dock keeps overflow accessible and pending progress outside metadata',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = await EditorHarness.create();
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'pending',
          owner: 0,
          fileName: 'pending.mp4',
          phase: AttachmentJobPhase.encrypting,
          bytes: 5,
          total: 10,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [job];
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: AttachmentStrip(viewModel: h.editor)),
          ),
        );
        await tester.pump();
        expect(find.text('Encrypting'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(AttachmentMoreButton), findsNothing);
        expect(find.byIcon(Icons.play_circle_outline), findsNothing);
        expect(find.byTooltip('Cancel attachment'), findsOneWidget);
        expect(h.editor.attachments, isEmpty);
        job.update(
          const AttachmentJobSnapshot(
            id: 'pending',
            owner: 0,
            fileName: 'pending.mp4',
            phase: AttachmentJobPhase.failed,
            error: 'Synthetic failure',
          ),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('More actions for pending.mp4'));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Remove pending'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        h.editor.attachmentsNotifier.value = [
          for (var i = 0; i < 6; i++)
            AttachmentModel(id: 'item$i', fileName: 'file$i.txt'),
        ];
        await tester.pump();
        expect(
          find.byKey(const ValueKey('attachment-overflow')),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('attachment-overflow')))
              .right,
          lessThanOrEqualTo(360),
        );
        await tester.tap(find.byKey(const ValueKey('attachment-overflow')));
        await tester.pumpAndSettle();
        expect(find.text('pending.mp4'), findsOneWidget);
        expect(find.byTooltip('Retry'), findsOneWidget);
        final layoutError = tester.takeException();
        expect(layoutError, isNull, reason: layoutError?.toString());
        await tester.ensureVisible(find.byTooltip('Remove pending'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove pending'));
        await tester.pumpAndSettle();
        expect(find.text('pending.mp4'), findsNothing);
        expect(h.editor.attachmentsNotifier.value.length, 6);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        job.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets('overflow gallery closes when the note identity changes', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    for (final id in ['first', 'second']) {
      h.seed(
        id,
        h.note(
          id,
          'body',
          attachments: [
            for (var i = 0; i < 6; i++)
              {'id': '$id$i', 'fileName': '$id$i.txt'},
          ],
        ),
      );
    }
    await h.editor.loadNote('first');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttachmentStrip(viewModel: h.editor)),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('attachment-overflow')));
      await tester.pumpAndSettle();
      expect(find.text('first5.txt'), findsOneWidget);
      await h.editor.loadNote('second');
      await tester.pumpAndSettle();
      expect(find.text('More attachments'), findsNothing);
      expect(find.text('first5.txt'), findsNothing);
      expect(h.files.writeAttempts, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      h.disposeEditor();
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(h.dispose);
    }
  });

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
      final cache = FakeOpenCache()
        ..gate = Completer<OperationResult<CachedAttachmentFile>>();
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
        await tester.tap(find.byKey(const ValueKey('attachment-open-video')));
        await tester.tap(find.byKey(const ValueKey('attachment-open-video')));
        expect(cache.opens, 1);
        cache.gate!.complete(
          const OperationResult.success(
            CachedAttachmentFile(
              'D:/synthetic-cache/demo.mp4',
              9 * 1024 * 1024,
              'synthetic',
            ),
          ),
        );
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
    'pending first attachment hides unavailable actions and retains inline cancellation',
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
        await tester.tap(find.textContaining('Attachments ('));
        await tester.pumpAndSettle();
        expect(find.text('Encrypting'), findsOneWidget);
        expect(
          tester
              .widget<InkWell>(
                find.byKey(const ValueKey('attachment-open-synthetic')),
              )
              .onTap,
          isNull,
        );
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(AttachmentMoreButton), findsNothing);
        expect(find.byIcon(Icons.play_circle_outline), findsNothing);
        expect(find.byTooltip('Cancel attachment'), findsOneWidget);
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
        expect(find.byTooltip('Cancel attachment'), findsNothing);
        expect(find.byType(AttachmentMoreButton), findsNothing);
        expect(find.byIcon(Icons.play_circle_outline), findsNothing);
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
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
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
