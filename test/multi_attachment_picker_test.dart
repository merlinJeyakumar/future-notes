import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/platform/directory_attachment_export.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'support/validation_directory.dart';
import 'support/editor_harness.dart';

class Picker extends FilePicker {
  FilePickerResult? result;
  Completer<FilePickerResult?>? gate;
  final multiple = <bool>[];
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    multiple.add(allowMultiple);
    return gate?.future ?? result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Picker picker;
  setUp(() {
    picker = Picker();
    FilePicker.platform = picker;
  });

  test(
    'attachment picker requests multiple; note import stays single',
    () async {
      final files = FileService();
      await files.pickAttachments();
      await files.pickFile(allowedExtensions: ['fnote']);
      expect(picker.multiple, [true, false]);
    },
  );

  test(
    'native multi-picker owns each grant and releases malformed results',
    () async {
      final run = await createValidationRun();
      final calls = <String>[];
      var invalid = false;
      const channel = MethodChannel('future_notes/documents');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(
              '${call.method}:${call.arguments is Map ? (call.arguments as Map)['lease'] ?? '' : ''}',
            );
            if (call.method == 'pickFiles')
              return [
                {
                  'lease': 'one',
                  'path': '/synthetic/one',
                  'name': 'same.txt',
                  'length': 4,
                  'identity': 'native-one',
                },
                {
                  'lease': 'two',
                  'path': '/synthetic/two',
                  'name': 'same.txt',
                  'length': invalid ? 'bad' : 5,
                  'identity': 'native-two',
                },
              ];
            return null;
          });
      final files = ProviderNoteFiles(
        documents: const MobileLibraryDocuments(
          kind: LibraryLocationKind.androidTree,
        ),
        location: const LibraryLocation(
          kind: LibraryLocationKind.androidTree,
          token: 'content://synthetic/tree',
        ),
        libraryId: '00000000-0000-4000-8000-000000000001',
        privateRoot: run.path,
      );
      try {
        final result = await files.pickAttachments();
        expect(result!.files.map((f) => f.name), ['same.txt', 'same.txt']);
        expect(result.files.map((f) => f.path).toSet(), hasLength(2));
        await files.releasePickedSource(result.files.first.path!);
        await files.releasePickedSource(result.files.last.path!);
        expect(
          calls.where((s) => s.startsWith('closePickedSource:')),
          hasLength(2),
        );
        invalid = true;
        await expectLater(files.pickAttachments(), throwsFormatException);
        expect(
          calls.where((s) => s.startsWith('closePickedSource:')),
          hasLength(4),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await deleteValidationRun(run);
      }
    },
  );

  test(
    'owned multi-intake creates independent jobs, preserves names and source bytes',
    () async {
      final run = await createValidationRun();
      final app = OwnedAppServices(
        environment: StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: '${run.path}/library',
          settingsFile: '${run.path}/settings/config.json',
        ),
      );
      expect((await app.initialize()).isSuccess, true);
      final editor = ContentViewModel(
        fileService: app.files,
        settings: app.settings,
        encryptionService: EncryptionService(),
        startBackgroundServices: false,
      );
      try {
        editor.titleController.text = 'Synthetic multi-intake';
        expect((await editor.saveNote()).isSuccess, true);
        final sources = [
          for (var i = 0; i < 3; i++)
            await File('${run.path}/source-$i').writeAsString('payload-$i'),
        ];
        picker.result = FilePickerResult([
          for (var i = 0; i < sources.length; i++)
            PlatformFile(
              name: i < 2 ? 'same.txt' : 'Unicode café.txt',
              path: sources[i].path,
              size: 9,
            ),
        ]);
        await editor.pickAttachment();
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (editor.hasAttachmentJobs && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(editor.hasAttachmentJobs, false);
        expect(
          editor.attachments.map((a) => a.fileName),
          containsAll(['same.txt', 'same.txt', 'Unicode café.txt']),
        );
        expect(editor.attachments.map((a) => a.id).toSet(), hasLength(3));
        expect(editor.attachmentJobsNotifier.value, hasLength(3));
        for (var i = 0; i < 3; i++)
          expect(await sources[i].readAsString(), 'payload-$i');
        final output = await DirectoryAttachmentExport.create(run.path);
        expect(
          (await editor.exportAttachments(
            editor.attachments.map((a) => a.id),
            output: output,
          )).isSuccess,
          true,
        );
        final names = await output.directory
            .list()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(
          names,
          containsAll(['same.txt', 'same (2).txt', 'Unicode café.txt']),
        );
        expect(editor.attachments, hasLength(3));
        picker.gate = Completer<FilePickerResult?>();
        final pending = editor.pickAttachment();
        while (picker.multiple.length < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await editor.pickAttachment();
        expect(picker.multiple, hasLength(2));
        expect((await editor.reset(discardChanges: true)).isSuccess, true);
        picker.gate!.complete(picker.result);
        await pending;
        expect(editor.attachments, isEmpty);
        expect(editor.hasAttachmentJobs, false);
        picker.gate = null;
        picker.result = null;
        await editor.pickAttachment();
        expect(editor.attachments, isEmpty);
      } finally {
        editor.dispose();
        await editor.closeLibraryResources();
        await app.close();
        await deleteValidationRun(run);
      }
    },
  );

  test('legacy batch export preserves filenames and originals', () async {
    final h = await EditorHarness.create();
    try {
      h.seed(
        'note_demo',
        h.note(
          'demo',
          'Synthetic body',
          attachments: [
            for (var i = 0; i < 2; i++)
              {'id': 'item-$i', 'fileName': 'same.txt', 'size': 3},
          ],
        ),
      );
      for (var i = 0; i < 2; i++) {
        h.files.attachmentContents['demo/item-$i'] = Uint8List.fromList([
          1,
          2,
          i,
        ]);
      }
      await h.editor.loadNote('note_demo');
      final output = await DirectoryAttachmentExport.create(h.run.path);
      final result = await h.editor.exportAttachments([
        'item-0',
        'item-1',
      ], output: output);
      expect(result.isSuccess, true, reason: result.message);
      expect(await File('${output.directory.path}/same.txt').readAsBytes(), [
        1,
        2,
        0,
      ]);
      expect(
        await File('${output.directory.path}/same (2).txt').readAsBytes(),
        [1, 2, 1],
      );
      expect(h.editor.attachments, hasLength(2));
      expect(h.files.attachmentContents, hasLength(2));
      expect(h.encryption.binaryDecryptCalls, 2);
    } finally {
      await h.dispose();
    }
  });

  test('cancelled directory export removes only owned outputs', () async {
    final run = await createValidationRun();
    try {
      final sentinel = await File(
        '${run.path}/preserve.txt',
      ).writeAsString('keep');
      final output = await DirectoryAttachmentExport.create(run.path);
      final path = await output.destination('../same.txt');
      await File(path).writeAsString('synthetic');
      await output.cleanup([path, sentinel.path]);
      expect(await output.directory.exists(), false);
      expect(await sentinel.readAsString(), 'keep');
    } finally {
      await deleteValidationRun(run);
    }
  });
}
