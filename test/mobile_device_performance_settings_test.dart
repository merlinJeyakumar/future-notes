import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/mobile/app_settings_dialog.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';

class _Settings extends SettingsService {
  _Settings()
    : super.withStorage(
        storage: StorageEnvironment.validation(
          validationRoot: 'D:/future-notes-validation-native-ui',
          dataRoot: 'D:/future-notes-validation-native-ui/library',
          settingsFile: 'D:/future-notes-validation-native-ui/settings.json',
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
    'mobile presets fit narrow dialogs and change only acknowledged settings',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
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
              loadVersion: () async => 'Synthetic',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('File compression'), findsNothing);
      expect(find.text('This device'), findsOneWidget);
      final fast = find.text('Higher throughput');
      await tester.ensureVisible(fast);
      await tester.tap(fast);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.targetPercent, 85);
      expect(settings.attachmentPerformance.maxParallel, 2);
      expect(settings.attachmentPerformance.checkBeforeOpen, false);
      settings.write = Completer<void>();
      final battery = find.text('Battery friendly');
      await tester.ensureVisible(battery);
      await tester.tap(battery);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.targetPercent, 85);
      settings.write!.completeError(StateError('synthetic write rejection'));
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.targetPercent, 85);
      expect(
        find.textContaining('previous value was retained'),
        findsOneWidget,
      );
      settings.write = null;
      final adaptive = find.text('Adaptive 70%');
      await tester.ensureVisible(adaptive);
      await tester.tap(adaptive);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance, AttachmentPerformance.defaults);
      await tester.ensureVisible(find.text('Advanced configuration'));
      await tester.tap(find.text('Advanced configuration'));
      await tester.pumpAndSettle();
      final check = find.byKey(const ValueKey('check-before-open'));
      final verify = find.byKey(const ValueKey('verify-after-open'));
      final backup = find.byKey(const ValueKey('validate-exported-backup'));
      final writes = find.byKey(const ValueKey('verify-large-file-writes'));
      expect(tester.widget<SwitchListTile>(writes).value, isFalse);
      expect(tester.widget<SwitchListTile>(check).value, isFalse);
      expect(tester.widget<SwitchListTile>(verify).value, isFalse);
      expect(tester.widget<SwitchListTile>(backup).value, isFalse);
      expect(
        find.text('Check encrypted files before opening/exporting'),
        findsOneWidget,
      );
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.exportChecks(mobile: true), (
        checkSource: true,
        verifyOutput: false,
      ));
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.exportChecks(mobile: true), (
        checkSource: true,
        verifyOutput: true,
      ));
      await tester.ensureVisible(backup);
      settings.write = Completer<void>();
      await tester.tap(backup);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.validateExportedBackup, isFalse);
      settings.write!.complete();
      await tester.pumpAndSettle();
      settings.write = null;
      expect(settings.attachmentPerformance.validateExportedBackup, isTrue);
      expect(settings.attachmentPerformance.checkBeforeOpen, isTrue);
      expect(settings.attachmentPerformance.verifyAfterOpen, isTrue);
      await tester.tap(backup);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.validateExportedBackup, isFalse);
      await tester.ensureVisible(writes);
      await tester.tap(writes);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance.verifyLargeFileWrites, isTrue);
      expect(settings.attachmentPerformance.checkBeforeOpen, isTrue);
      final reset = find.text('Reset performance defaults');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(settings.attachmentPerformance, AttachmentPerformance.defaults);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.attachmentPerformanceNotifier.dispose();
      settings.themeModeNotifier.dispose();
    },
  );
}
