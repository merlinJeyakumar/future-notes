import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_strip.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_viewer.dart';
import 'package:flutter_application_1/features/dashboard/mobile/mobile_theme.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'support/editor_harness.dart';

Future<EditorHarness> fixture(
  WidgetTester tester, {
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = await EditorHarness.create();
  harness.seed(
    'demo',
    harness.note(
      'demo',
      'Synthetic body',
      attachments: [
        for (var i = 0; i < 12; i++)
          {
            'id': 'synthetic-$i-0000$i',
            'fileName': i < 2
                ? 'Project overview.pdf'
                : i == 2
                ? 'Workshop recording.mp4'
                : 'Long synthetic document filename $i.docx',
            'size': 1024 * 1024,
          },
      ],
    ),
  );
  await harness.editor.loadNote('demo');
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? MobileTheme.dark
          : MobileTheme.light,
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('synthetic-attachment-screen'),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: TextField(key: ValueKey('editor'))),
            AttachmentStrip(viewModel: harness.editor),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    harness.disposeEditor();
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(harness.dispose);
  });
  return harness;
}

Future<void> captureSyntheticScreen(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('synthetic-attachment-screen')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ImageByteFormat.png);
      await File(
        '.validation/mobile-attachments-$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  testWidgets(
    'mobile collapsed icons, bounded rows and full-screen search read no payload',
    (tester) async {
      final h = await fixture(tester);
      expect(find.text('Project overview.pdf'), findsNothing);
      expect(find.byKey(const ValueKey('attachment-overflow')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('attachment-expand-toggle')));
      await tester.pumpAndSettle();
      final dock = find.byType(AttachmentStrip);
      expect(tester.getSize(dock).height, lessThan(300));
      final first = find.byKey(
        const ValueKey('attachment-open-synthetic-0-00000'),
      );
      final rowRect = tester.getRect(first);
      expect(rowRect.width, greaterThan(300));
      expect(rowRect.height, lessThan(120));
      expect(find.text('PDF · 1.0 MiB · 00000'), findsOneWidget);
      await captureSyntheticScreen(tester, 'dock');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('attachment-open-synthetic-11-000011')),
        150,
        scrollable: find.descendant(
          of: dock,
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find
            .byKey(const ValueKey('attachment-open-synthetic-11-000011'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('attachment-show-all')));
      await tester.pumpAndSettle();
      expect(find.text('All attachments'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Close'), findsNothing);
      await captureSyntheticScreen(tester, 'gallery');
      final gallery = find.byKey(const ValueKey('attachment-gallery-list'));
      final search = find.byKey(const ValueKey('attachment-filename-search'));
      expect(tester.getSize(gallery).width, 360);
      await tester.enterText(search, '  WORKSHOP ');
      await tester.pumpAndSettle();
      expect(find.text('Workshop recording.mp4'), findsOneWidget);
      expect(find.byType(AttachmentMoreButton).hitTestable(), findsOneWidget);
      final filtered = find
          .byKey(const ValueKey('attachment-open-synthetic-2-00002'))
          .last;
      expect(tester.getRect(filtered).left, tester.getRect(search).left);
      await tester.enterText(search, 'no matching synthetic file');
      await tester.pumpAndSettle();
      expect(find.text('No matching attachments'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear attachment search'));
      await tester.pumpAndSettle();
      expect(find.text('No matching attachments'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('All attachments'), findsNothing);
      expect(h.encryption.binaryDecryptCalls, 0);
      expect(h.files.writeAttempts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'large text and narrow ${brightness.name} mobile rows remain scrollable',
      (tester) async {
        final h = await fixture(tester, scale: 2, brightness: brightness);
        await tester.tap(
          find.byKey(const ValueKey('attachment-expand-toggle')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('attachment-show-all')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final search = find.byKey(const ValueKey('attachment-filename-search'));
        await tester.enterText(search, 'document filename 11');
        await tester.pumpAndSettle();
        expect(
          find.text('Long synthetic document filename 11.docx'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        h.editor.isLockedNotifier.value = true;
        await tester.pump();
        expect(
          find.text('Long synthetic document filename 11.docx'),
          findsNothing,
        );
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(h.encryption.binaryDecryptCalls, 0);
      },
    );
  }

  testWidgets(
    'selection uses metadata only, filtered Select all and cancellable removal',
    (tester) async {
      final h = await fixture(tester);
      await tester.tap(find.byKey(const ValueKey('attachment-show-all')));
      await tester.pumpAndSettle();
      expect(find.text('12 attachments'), findsOneWidget);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('12')),
        findsNothing,
      );
      expect(appBar.actions, isNotEmpty);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      final search = find.byKey(const ValueKey('attachment-filename-search'));
      await tester.enterText(search, 'Workshop');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all visible attachments'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('1 of 12 attachments'), findsOneWidget);
      await captureSyntheticScreen(tester, 'selection');
      await tester.tap(
        find.byKey(const ValueKey('attachment-remove-selected')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove 2 attachments?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.editor.attachments.length, 12);
      expect(h.files.writeAttempts, 0);
      expect(h.encryption.binaryDecryptCalls, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('All attachments'), findsOneWidget);
      expect(find.text('2 selected'), findsNothing);
      await tester.enterText(search, 'Project');
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(const ValueKey('attachment-open-synthetic-1-00001')).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('attachment-remove-selected')),
      );
      await tester.pumpAndSettle();
      h.editor.isLockedNotifier.value = true;
      await tester.pump();
      expect(find.text('Remove 1 attachment?'), findsNothing);
      expect(find.text('Project overview.pdf'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'row progress preserves geometry, safe actions and note ownership',
    (tester) async {
      final h = await fixture(tester);
      final owner = h.editor.draftSession.generation;
      final job = AttachmentJobState(
        AttachmentJobSnapshot(
          id: 'view-job',
          owner: owner,
          originalAttachmentId: 'synthetic-0-00000',
          operation: AttachmentJobOperation.open,
          fileName: 'Project overview.pdf',
          phase: AttachmentJobPhase.decrypting,
          bytes: 1,
          total: 100,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [job];
      addTearDown(job.dispose);
      await tester.tap(find.byKey(const ValueKey('attachment-expand-toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      final row = find.byKey(
        const ValueKey('attachment-open-synthetic-0-00000'),
      );
      final rect = tester.getRect(row);
      expect(tester.widget<InkWell>(row).onTap, isNull);
      expect(
        find.descendant(of: row, matching: find.byType(AttachmentMoreButton)),
        findsNothing,
      );
      expect(find.byTooltip('Cancel attachment').hitTestable(), findsOneWidget);
      job.update(
        AttachmentJobSnapshot(
          id: 'view-job',
          owner: owner,
          originalAttachmentId: 'synthetic-0-00000',
          operation: AttachmentJobOperation.open,
          fileName: 'Project overview.pdf',
          phase: AttachmentJobPhase.decrypting,
          bytes: 100,
          total: 100,
        ),
      );
      await tester.pump();
      expect(tester.getRect(row), rect);
      job.update(
        AttachmentJobSnapshot(
          id: 'view-job',
          owner: owner,
          originalAttachmentId: 'synthetic-0-00000',
          operation: AttachmentJobOperation.open,
          fileName: 'Project overview.pdf',
          phase: AttachmentJobPhase.finalizing,
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Cancel attachment'), findsNothing);
      job.update(
        AttachmentJobSnapshot(
          id: 'view-job',
          owner: owner,
          originalAttachmentId: 'synthetic-0-00000',
          operation: AttachmentJobOperation.open,
          fileName: 'Project overview.pdf',
          phase: AttachmentJobPhase.completed,
        ),
      );
      await tester.pump();
      expect(tester.widget<InkWell>(row).onTap, isNotNull);
      expect(
        find.descendant(of: row, matching: find.byType(AttachmentMoreButton)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('attachment-show-all')));
      await tester.pumpAndSettle();
      h.seed('another', h.note('another', 'Synthetic second body'));
      await h.editor.loadNote('another');
      await tester.pump();
      expect(find.text('All attachments'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
