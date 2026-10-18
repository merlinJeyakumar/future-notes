import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/widgets/app_settings_dialog.dart';

class _Settings extends SettingsService {
  _Settings()
    : super.withStorage(
        storage: StorageEnvironment.validation(
          validationRoot: 'D:/future-notes-validation-ui',
          dataRoot: 'D:/future-notes-validation-ui/library',
          settingsFile: 'D:/future-notes-validation-ui/config/settings.json',
        ),
      );
  Completer<void>? write;
  @override
  Future<String> getUserDataPath() async => 'Synthetic library';
  @override
  Future<void> setAttachmentPerformance(AttachmentPerformance value) async {
    await write?.future;
    attachmentPerformanceNotifier.value = value;
  }
}

void main() {
  testWidgets(
    'performance target and advanced limits await acknowledgement and retain failed values',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = _Settings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSettingsDialog(
              settings: settings,
              pickLibrary: () async => null,
              openLibrary: (_) async => const OperationResult.success(),
              loadVersion: () async => 'Synthetic version',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Available-capacity target: 70%'), findsOneWidget);
      await tester.tap(find.text('Advanced configuration'));
      await tester.pumpAndSettle();
      final check = find.byKey(const ValueKey('check-before-open'));
      final verify = find.byKey(const ValueKey('verify-after-open'));
      expect(tester.widget<SwitchListTile>(check).value, isFalse);
      expect(tester.widget<SwitchListTile>(verify).value, isFalse);
      final backup = find.byKey(const ValueKey('validate-exported-backup'));
      final writes = find.byKey(const ValueKey('verify-large-file-writes'));
      expect(tester.widget<SwitchListTile>(backup).value, isFalse);
      expect(tester.widget<SwitchListTile>(writes).value, isFalse);
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.checkBeforeOpen, isTrue);
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.verifyAfterOpen, isTrue);
      final parallel = find.byType(DropdownButtonFormField<int>).first;
      await tester.ensureVisible(parallel);
      await tester.tap(parallel);
      await tester.pumpAndSettle();
      settings.write = Completer<void>();
      await tester.tap(find.text('2 files').last);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.maxParallel, 0);
      settings.write!.completeError(StateError('synthetic write failure'));
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.maxParallel, 0);
      expect(
        find.textContaining('previous value was retained'),
        findsOneWidget,
      );
      settings.write = null;
      await tester.tap(parallel);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 files').last);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.maxParallel, 2);
      for (final option in [backup, writes]) {
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }
      expect(settings.attachmentPerformance.validateExportedBackup, isTrue);
      expect(settings.attachmentPerformance.verifyLargeFileWrites, isTrue);
      final reset = find.text('Reset performance defaults');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance, AttachmentPerformance.defaults);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.attachmentPerformanceNotifier.dispose();
      settings.themeModeNotifier.dispose();
    },
  );
}
