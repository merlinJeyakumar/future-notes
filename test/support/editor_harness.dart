import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/decryption_result.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import 'validation_directory.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/platform/windows_desktop_actions.dart';

class PausePoint {
  final started = Completer<void>();
  final release = Completer<void>();

  Future<void> wait() async {
    if (!started.isCompleted) started.complete();
    await release.future;
  }

  void resume() {
    if (!release.isCompleted) release.complete();
  }
}

class EditorHarness {
  EditorHarness._(
    this.run,
    this.settings,
    this.files,
    this.encryption,
    DraftDecisionHandler? onDraftDecision, {
    AttachmentOpenCache? attachmentOpenCache,
    DesktopActions? desktopActions,
    Future<List<dynamic>> Function(String)? htmlToDelta,
    Future<String> Function(List<dynamic>)? deltaToHtml,
  }) {
    editor = ContentViewModel(
      fileService: files,
      encryptionService: encryption,
      settings: settings,
      startBackgroundServices: false,
      nowMilliseconds: () => 1700000000000,
      onDraftDecision: onDraftDecision,
      attachmentOpenCache: attachmentOpenCache,
      desktopActions: desktopActions,
      htmlToDelta: htmlToDelta,
      deltaToHtml: deltaToHtml,
    );
  }

  static Future<EditorHarness> create({
    DraftDecisionHandler? onDraftDecision,
    AttachmentOpenCache? attachmentOpenCache,
    DesktopActions? desktopActions,
    Future<List<dynamic>> Function(String)? htmlToDelta,
    Future<String> Function(List<dynamic>)? deltaToHtml,
  }) async {
    // Widget tests run in fake async. Synchronous creation of this empty,
    // disposable directory avoids an OS future that fake async cannot resolve.
    final run = Directory.systemTemp.createTempSync('future-notes-validation-');
    final library = p.join(run.path, 'library');
    final settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: library,
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
      documentsDirectoryResolver: () async {
        throw StateError('Production storage resolution is forbidden.');
      },
    );
    return EditorHarness._(
      run,
      settings,
      MemoryNoteFiles(library),
      SyntheticCipher(),
      onDraftDecision,
      attachmentOpenCache: attachmentOpenCache,
      desktopActions: desktopActions,
      htmlToDelta: htmlToDelta,
      deltaToHtml: deltaToHtml,
    );
  }

  final Directory run;
  final SettingsService settings;
  final MemoryNoteFiles files;
  final SyntheticCipher encryption;
  late final ContentViewModel editor;
  bool disposed = false;

  void disposeEditor() {
    if (disposed) return;
    disposed = true;
    editor.dispose();
  }

  Future<void> dispose() async {
    disposeEditor();
    settings.themeModeNotifier.dispose();
    await deleteValidationRun(run);
  }

  Map<String, dynamic> note(
    String id,
    String text, {
    bool locked = false,
    List<dynamic> attachments = const [],
  }) => {
    'id': id,
    'title': 'Synthetic title $id',
    'content': locked ? encryption.wrapUser(text, 'synthetic-password') : text,
    'isLocked': locked,
    'timestamp': 1700000000000,
    'attachments': attachments,
  };

  void seed(
    String name,
    Map<String, dynamic> metadata, {
    bool encrypted = true,
    NoteStorageFormat? format,
  }) => files.seed(
    name,
    encrypted ? encryption.wrapApp(jsonEncode(metadata)) : jsonEncode(metadata),
    format: format,
  );

  Future<Map<String, dynamic>> decoded(String name, {String? root}) async {
    final reference = files.reference(name, root: root);
    final raw = files.contents[reference.contentPath]!;
    return jsonDecode(
          raw.startsWith('app:') ? await encryption.decryptApp(raw) : raw,
        )
        as Map<String, dynamic>;
  }
}

/// Intentionally synthetic cipher; real wire compatibility remains covered by
/// the Stage 0 fixtures. These controllable promises exercise VM interleavings.
class SyntheticCipher implements IEncryptionService {
  PausePoint? nextAppEncryption;
  PausePoint? nextDecryption;
  int encryptCalls = 0;
  int binaryDecryptCalls = 0;
  bool failBinaryDecryption = false;

  String wrapApp(String text) => 'app:${base64Encode(utf8.encode(text))}';
  String wrapUser(String text, String password) =>
      'user:${base64Encode(utf8.encode(password))}:${base64Encode(utf8.encode(text))}';

  @override
  Future<String> encryptApp(String text) async {
    encryptCalls++;
    final pause = nextAppEncryption;
    nextAppEncryption = null;
    if (pause != null) await pause.wait();
    return wrapApp(text);
  }

  @override
  Future<String> decryptApp(String text) async {
    final result = await decryptAppResult(text);
    return result.isSuccess ? result.value! : '';
  }

  @override
  Future<DecryptionResult<String>> decryptAppResult(String text) async {
    if (!text.startsWith('app:'))
      return const DecryptionResult.failure(
        DecryptionFailure.invalidCiphertext,
      );
    try {
      return DecryptionResult.success(
        utf8.decode(base64Decode(text.substring(4))),
      );
    } catch (_) {
      return const DecryptionResult.failure(
        DecryptionFailure.invalidCiphertext,
      );
    }
  }

  @override
  Future<String> encrypt(String text, {String? password}) async {
    encryptCalls++;
    return wrapUser(text, password ?? 'synthetic-app-key');
  }

  @override
  Future<String> decrypt(String text, {String? password}) async {
    final result = await decryptResult(text, password: password);
    return result.isSuccess
        ? result.value!
        : 'Error decrypting: synthetic mismatch';
  }

  @override
  Future<DecryptionResult<String>> decryptResult(
    String text, {
    String? password,
  }) async {
    final pause = nextDecryption;
    nextDecryption = null;
    if (pause != null) await pause.wait();
    final prefix =
        'user:${base64Encode(utf8.encode(password ?? 'synthetic-app-key'))}:';
    if (!text.startsWith(prefix))
      return const DecryptionResult.failure(
        DecryptionFailure.invalidCiphertext,
      );
    return DecryptionResult.success(
      utf8.decode(base64Decode(text.substring(prefix.length))),
    );
  }

  @override
  Future<Uint8List> encryptBinary(Uint8List data, {String? password}) async =>
      data;
  @override
  Future<Uint8List> decryptBinary(Uint8List data, {String? password}) async =>
      data;
  @override
  Future<DecryptionResult<Uint8List>> decryptBinaryResult(
    Uint8List data, {
    String? password,
  }) async {
    binaryDecryptCalls++;
    return failBinaryDecryption
        ? const DecryptionResult.failure(DecryptionFailure.invalidCiphertext)
        : DecryptionResult.success(data);
  }
}

class MemoryNoteFiles implements IFileService {
  MemoryNoteFiles(this.libraryRoot);

  String libraryRoot;
  final contents = <String, String>{};
  final formats = <String, NoteStorageFormat>{};
  final attachmentContents = <String, Uint8List>{};
  final readPauses = <String, PausePoint>{};
  final writes = <NoteReference>[];
  int writeAttempts = 0;
  int pickerCalls = 0;
  bool failWrites = false;

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    pickerCalls++;
    return null; // Simulated user cancellation; no native picker.
  }

  NoteReference reference(String name, {String? root, String? id}) {
    final binding = StorageBinding(root ?? libraryRoot, 1);
    final format =
        formats[name] ??
        (name.startsWith('note_')
            ? NoteStorageFormat.folder
            : NoteStorageFormat.legacyFile);
    final path = format == NoteStorageFormat.folder
        ? binding.child('$name/note_content_${name.substring(5)}.enc')
        : binding.child(name);
    return NoteReference(
      binding: binding,
      fileName: name,
      format: format,
      contentPath: path,
      attachmentLocation: binding.child('$name/attachments'),
      modelId: id,
    );
  }

  void seed(String name, String encoded, {NoteStorageFormat? format}) {
    if (format != null) formats[name] = format;
    contents[reference(name).contentPath] = encoded;
  }

  @override
  Future<NoteReference?> resolveNote(String name) async {
    final ref = reference(name);
    return contents.containsKey(ref.contentPath) ? ref : null;
  }

  @override
  Future<NoteReference> newNoteReference(String id) async =>
      reference('note_$id', id: id);

  @override
  Future<String?> readResolved(NoteReference ref) async {
    final value = contents[ref.contentPath];
    final pause = readPauses.remove(ref.fileName);
    if (pause != null) await pause.wait();
    return value;
  }

  @override
  Future<NoteReference> writeResolved(NoteReference ref, String content) async {
    writeAttempts++;
    if (failWrites) throw const FileSystemException('Synthetic write failure');
    contents[ref.contentPath] = content;
    writes.add(ref);
    return ref;
  }

  @override
  Future<Uint8List?> readAttachment(String noteId, String attachmentId) async =>
      attachmentContents['$noteId/$attachmentId'];

  /// Any accidental fallback to native/unreviewed service operations fails.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected file-service operation: ${invocation.memberName}',
  );
}
