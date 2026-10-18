import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/mobile_export.dart';
import 'package:flutter_application_1/core/platform/prepared_mobile_export.dart';
import 'package:flutter_application_1/features/dashboard/mobile/export_progress_dialog.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'support/editor_harness.dart';

class ReadyFile extends PreparedMobileExport {
  ReadyFile(String path)
    : super(
        path: path,
        note: 'synthetic',
        key: 'snapshot',
        length: 1024,
        modifiedMicros: 0,
      );
  @override
  Future<bool> isCurrent() async => true;
}

class ReadyModel extends ContentViewModel {
  ReadyModel(EditorHarness h, this.file)
    : super(
        fileService: h.files,
        settings: h.settings,
        encryptionService: h.encryption,
        startBackgroundServices: false,
      );
  final PreparedMobileExport file;
  @override
  PreparedMobileExport? preparedExportForJob(String id) => file;
}

void main() {
  testWidgets(
    'ready export offers explicit native Save/Share and stays open for retries',
    (tester) async {
      const files = MethodChannel('future_notes/files');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final h = await EditorHarness.create();
      final cache = Directory('${h.run.path}/cache')..createSync();
      messenger.setMockMethodCallHandler(paths, (_) async => cache.path);
      final path = (await tester.runAsync(
        () => MobileExport.destination('Project notes.fnote'),
      ))!;
      File(path).writeAsBytesSync(List.filled(1024, 7));
      final model = ReadyModel(h, ReadyFile(path));
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'ready',
          owner: 0,
          fileName: 'Export package',
          phase: AttachmentJobPhase.completed,
          operation: AttachmentJobOperation.export,
          detail: 'Using prepared export',
        ),
      );
      final calls = <String>[];
      var save = Completer<bool>();
      messenger.setMockMethodCallHandler(files, (call) async {
        calls.add(call.method);
        expect((call.arguments as Map)['path'], path);
        if (call.method == 'saveExport') return save.future;
        return true;
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    showMobileExportProgress(
                      context: context,
                      model: model,
                      existingJob: job,
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Export ready'), findsOneWidget);
        expect(find.text('Using prepared export'), findsOneWidget);
        expect(
          calls,
          isEmpty,
        ); // Completion never launches a picker automatically.
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(calls, ['saveExport']);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
              .onPressed,
          isNull,
        );
        await messenger.handlePlatformMessage(
          'future_notes/files',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('exportSaveProgress', {
              'bytes': 512,
              'total': 1024,
            }),
          ),
          (_) {},
        );
        await tester.pump();
        expect(find.text('Saving file'), findsOneWidget);
        expect(find.text('512 B / 1.0 KiB · 50%'), findsOneWidget);
        save.complete(false);
        await tester.pumpAndSettle();
        expect(find.text('Save cancelled.'), findsOneWidget);
        expect(find.byType(MobileExportProgressDialog), findsOneWidget);
        expect(File(path).existsSync(), isTrue);
        save = Completer<bool>();
        await tester.tap(find.text('Save'));
        await tester.pump();
        save.completeError(PlatformException(code: 'storage_full'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Your export is still available'),
          findsOneWidget,
        );
        expect(File(path).existsSync(), isTrue);
        save = Completer<bool>();
        await tester.tap(find.text('Save'));
        await tester.pump();
        save.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Saved to files.'), findsOneWidget);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(calls, [
          'saveExport',
          'saveExport',
          'saveExport',
          'shareExport',
        ]);
        expect(find.byType(MobileExportProgressDialog), findsOneWidget);
        expect(File(path).existsSync(), isTrue);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileExportProgressDialog), findsNothing);
        expect(
          File(path).existsSync(),
          isTrue,
        ); // The session cache owns the file.
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        job.dispose();
        await tester.runAsync(() => MobileExport.discardAll([path]));
        messenger.setMockMethodCallHandler(files, null);
        messenger.setMockMethodCallHandler(paths, null);
        await tester.runAsync(h.dispose);
      }
    },
  );
}
