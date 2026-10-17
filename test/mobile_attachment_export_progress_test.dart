import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/attachment_batch_export.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_progress.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_strip.dart';
import 'package:flutter_application_1/features/dashboard/mobile/mobile_theme.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'mobile_attachment_presentation_test.dart' as presentation;
import 'support/editor_harness.dart';

class ControlledExport extends ContentViewModel {
  ControlledExport(EditorHarness h)
    : super(
        fileService: h.files,
        settings: h.settings,
        encryptionService: h.encryption,
        startBackgroundServices: false,
      );
  final completion = Completer<OperationResult<void>>();
  late AttachmentJobState exportJob;
  int cancellations = 0;
  @override
  Future<OperationResult<void>> exportAttachments(
    Iterable<String> ids, {
    required AttachmentBatchExport output,
  }) {
    exportJob = AttachmentJobState(
      snapshot(AttachmentJobPhase.preparing, 0, 700),
    );
    attachmentJobsNotifier.value = [exportJob];
    return completion.future;
  }

  AttachmentJobSnapshot snapshot(
    AttachmentJobPhase phase,
    int mib,
    int total, {
    String file = 'File 1 of 2 · Workshop recording.mp4',
  }) => AttachmentJobSnapshot(
    id: 'synthetic-export',
    owner: draftSession.generation,
    fileName: '2 attachments',
    batch: true,
    operation: AttachmentJobOperation.export,
    phase: phase,
    detail: file,
    bytes: mib * 1024 * 1024,
    total: total * 1024 * 1024,
  );
  @override
  Future<void> cancelAttachmentJob(String id) async {
    cancellations++;
    exportJob.update(snapshot(AttachmentJobPhase.cancelling, 350, 700));
  }
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'gallery export shows live per-file stages and bytes at text scale $scale',
      (tester) async {
        final h = await presentation.fixture(tester);
        final model = ControlledExport(h);
        await model.loadNote('demo');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          model.exportJob.dispose();
          model.dispose();
          await model.closeLibraryResources();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: MobileTheme.dark,
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('synthetic-attachment-screen'),
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: Scaffold(body: AttachmentStrip(viewModel: model)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('attachment-show-all')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox).at(0));
        await tester.pump();
        await tester.tap(find.byType(Checkbox).at(1));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('attachment-share-selected')),
        );
        await tester.pump();
        expect(find.text('Preparing selected attachments…'), findsNothing);
        final progress = find.byType(MobileAttachmentJobProgress);
        expect(progress, findsOneWidget);
        expect(find.text('Checking attachment…'), findsOneWidget);
        model.exportJob.update(
          model.snapshot(AttachmentJobPhase.decrypting, 350, 700),
        );
        await tester.pump();
        expect(find.text('Decrypting'), findsOneWidget);
        expect(
          find.text('File 1 of 2 · Workshop recording.mp4'),
          findsOneWidget,
        );
        expect(find.text('350 MiB / 700 MiB · 50%'), findsOneWidget);
        final bar = find.descendant(
          of: progress,
          matching: find.byType(LinearProgressIndicator),
        );
        expect(tester.widget<LinearProgressIndicator>(bar).value, .5);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('attachment-share-selected')),
              )
              .onPressed,
          isNull,
        );
        await presentation.captureSyntheticScreen(
          tester,
          'export-progress-${scale.toInt()}x',
        );
        model.exportJob.update(
          model.snapshot(AttachmentJobPhase.verifying, 700, 700),
        );
        await tester.pump();
        expect(find.text('Verifying'), findsOneWidget);
        expect(find.text('Completed'), findsNothing);
        model.exportJob.update(
          model.snapshot(
            AttachmentJobPhase.decrypting,
            350,
            1400,
            file: 'File 2 of 2 · Second video.mp4',
          ),
        );
        await tester.pump();
        expect(find.text('File 2 of 2 · Second video.mp4'), findsOneWidget);
        expect(find.text('350 MiB / 1.4 GiB · 25%'), findsOneWidget);
        expect(tester.widget<LinearProgressIndicator>(bar).value, .25);
        await tester.tap(find.text('Cancel export'));
        await tester.pump();
        expect(model.cancellations, 1);
        expect(find.text('Cancelling…'), findsOneWidget);
        expect(find.text('Cancel export'), findsNothing);
        expect(tester.widget<LinearProgressIndicator>(bar).value, isNull);
        model.exportJob.update(
          model.snapshot(AttachmentJobPhase.cancelled, 0, 0),
        );
        model.attachmentJobsNotifier.value = List.of(
          model.attachmentJobsNotifier.value,
        );
        model.completion.complete(
          const OperationResult.failure(
            OperationOutcome.cancelled,
            'Export cancelled.',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MobileAttachmentJobProgress), findsNothing);
        expect(find.text('2 selected'), findsOneWidget);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
