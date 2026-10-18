import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/file_operation_progress.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/widgets/note_import_dialog.dart';
import 'note_replacement_dialog_test.dart' show conflict;

void main() {
  for (final choice in NoteImportDecision.values) {
    testWidgets('mobile large-text duplicate options allow ${choice.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final jobs = ValueNotifier<List<AttachmentJobState>>([]);
      NoteImportDecision? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: NoteImportDialog(
            fileName: 'Synthetic.fnote',
            jobs: jobs,
            detailedProgress: true,
            cancelJob: (_) async {},
            startImport: (resolve) async {
              selected = await resolve(conflict(null));
              return const OperationResult.success(
                NoteImportResult(NoteImportDisposition.ignored, 'synthetic'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This note already exists'), findsOneWidget);
      final label = switch (choice) {
        NoteImportDecision.duplicate => 'Duplicate',
        NoteImportDecision.replace => 'Back up & Replace',
        NoteImportDecision.ignore => 'Ignore',
      };
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(selected, choice);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
    });
  }

  testWidgets(
    'mobile import shows live file, bytes and percent through publication',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final jobs = ValueNotifier<List<AttachmentJobState>>([]);
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'synthetic-import',
          owner: 1,
          fileName: 'Import package',
          operation: AttachmentJobOperation.import,
          phase: AttachmentJobPhase.preparing,
          bytes: 320 * 1024 * 1024,
          total: 708 * 1024 * 1024,
          detail: 'Extracting package · File 2 of 4\nSample video.mp4',
        ),
      );
      final done = Completer<OperationResult<NoteImportResult>>();
      await tester.pumpWidget(
        MaterialApp(
          home: NoteImportDialog(
            fileName: 'Synthetic.fnote',
            detailedProgress: true,
            jobs: jobs,
            startImport: (_) {
              jobs.value = [job];
              return done.future;
            },
            cancelJob: (_) async {},
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('File 2 of 4'), findsOneWidget);
      expect(find.textContaining('Sample video.mp4'), findsOneWidget);
      expect(find.text('320 MiB / 708 MiB · 45%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(320 / 708, .0001),
      );
      job.update(
        const AttachmentJobSnapshot(
          id: 'synthetic-import',
          owner: 1,
          fileName: 'Import package',
          operation: AttachmentJobOperation.import,
          phase: AttachmentJobPhase.finalizing,
          bytes: 708 * 1024 * 1024,
          total: 708 * 1024 * 1024,
          detail: 'Saving encrypted files · File 2 of 4\nSample video.mp4',
          fileProgress: FileOperationProgress(
            stage: 'Saving encrypted files',
            fileName: 'Sample video.mp4',
            fileIndex: 2,
            fileCount: 4,
            bytes: 320 * 1024 * 1024,
            total: 708 * 1024 * 1024,
            overallBytes: 940 * 1024 * 1024,
            overallTotal: 1800 * 1024 * 1024,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('320 MiB / 708 MiB · 45%'), findsOneWidget);
      expect(find.text('940 MiB / 1.8 GiB · 52%'), findsOneWidget);
      expect(find.text('Current file'), findsOneWidget);
      expect(find.text('Overall saving'), findsOneWidget);
      final indicators = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(indicators[0].value, closeTo(320 / 708, .0001));
      expect(indicators[1].value, closeTo(940 / 1800, .0001));
      job.update(
        const AttachmentJobSnapshot(
          id: 'synthetic-import',
          owner: 1,
          fileName: 'Import package',
          operation: AttachmentJobOperation.import,
          phase: AttachmentJobPhase.finalizing,
          detail:
              'Finishing import\nSaving note details and recovery information',
          fileProgress: FileOperationProgress(
            stage: 'Finishing import',
            fileName: 'Note details',
            fileIndex: 4,
            fileCount: 4,
            bytes: 0,
            total: 0,
            overallBytes: 1800,
            overallTotal: 1800,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(
        find.textContaining('Saving note details and recovery information'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Finishing…'))
            .onPressed,
        isNull,
      );
      done.complete(
        const OperationResult.success(
          NoteImportResult(NoteImportDisposition.created, 'synthetic'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Note imported'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
      job.dispose();
    },
  );
}
