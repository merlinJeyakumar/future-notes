import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'support/editor_harness.dart';

class GrantedHeaderFiles extends FileService implements ImportSourceReader {
  GrantedHeaderFiles(SettingsService settings) : super(settings: settings);
  @override
  bool get usesOwnedStorage => true;
  Uint8List header = Uint8List.fromList([0x4e, 0x4f, 0x54, 0x45, 1, 0]);
  String? requestedSource;
  bool revoked = false;
  @override
  Future<Uint8List> readImportHeader(String source) async {
    requestedSource = source;
    if (revoked) throw const FileSystemException('Synthetic revoked grant');
    return header;
  }
}

class NativeHeaderFiles extends FileService {
  NativeHeaderFiles(SettingsService settings) : super(settings: settings);
  @override
  bool get usesOwnedStorage => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'picked grants use their reader without reopening an inaccessible path',
    () async {
      final h = await EditorHarness.create();
      final files = GrantedHeaderFiles(h.settings);
      final editor = ContentViewModel(
        fileService: files,
        settings: h.settings,
        encryptionService: h.encryption,
        startBackgroundServices: false,
      );
      const source = '/synthetic/grant-only/export.fnote';
      try {
        for (final bytes in [
          [0x4e, 0x4f, 0x54, 0x45, 1, 0],
          [0x4e, 0x4f, 0x54, 0x45, 1, 1],
          [0x50, 0x4b, 3, 4, 0, 0],
        ]) {
          files.header = Uint8List.fromList(bytes);
          final result = await editor.verifyImportFile(
            PlatformFile(name: 'export.fnote', path: source, size: 6),
          );
          expect(result.isValid, true, reason: result.message);
          expect(result.isPack, true);
          expect(result.isPackEncrypted, bytes[0] == 0x4e && bytes[5] == 1);
          expect(files.requestedSource, source);
        }
        files.revoked = true;
        final rejected = await editor.verifyImportFile(
          PlatformFile(name: 'export.fnote', path: source, size: 6),
        );
        expect(rejected.isValid, false);
        expect(rejected.message, 'The import source could not be read.');
        expect(editor.attachments, isEmpty);
      } finally {
        editor.dispose();
        await editor.closeLibraryResources();
        await h.dispose();
      }
    },
  );
  test('desktop import keeps its native file reader', () async {
    final h = await EditorHarness.create();
    final editor = ContentViewModel(
      fileService: NativeHeaderFiles(h.settings),
      settings: h.settings,
      encryptionService: h.encryption,
      startBackgroundServices: false,
    );
    try {
      final source = await File(
        '${h.run.path}/export.fnote',
      ).writeAsBytes([0x4e, 0x4f, 0x54, 0x45, 1, 0]);
      final result = await editor.verifyImportFile(
        PlatformFile(name: 'export.fnote', path: source.path, size: 6),
      );
      expect(result.isValid, true, reason: result.message);
      expect(result.isPack, true);
      expect(result.isPackEncrypted, false);
      expect(await source.length(), 6);
    } finally {
      editor.dispose();
      await editor.closeLibraryResources();
      await h.dispose();
    }
  });
}
