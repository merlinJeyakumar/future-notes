import 'package:file_picker/file_picker.dart';

import '../../../core/platform/macos_file_access.dart';
import '../../../core/storage/storage_owner_worker.dart';
import '../../../core/storage/note_reference.dart';
import '../../../core/storage/library_watch.dart';
import 'file_service.dart';
import 'settings_service.dart';

/// Each picked input keeps a native scope until the existing job's finally
/// block releases it. Windows/mobile services retain their original classes.
class MacosFileService extends FileService implements PickedSourceOwner {
  MacosFileService({
    required SettingsService settings,
    required StorageOwner storageOwner,
    MacosFileAccess access = const MacosFileAccess(),
    MacosLibraryGrant? initialLibrary,
  }) : _access = access,
       _settings = settings,
       super(settings: settings, storageOwner: storageOwner) {
    if (initialLibrary != null)
      _libraries[initialLibrary.path] = initialLibrary;
  }

  final MacosFileAccess _access;
  final SettingsService _settings;
  final _inputs = <String, List<MacosInputGrant>>{};
  final _libraries = <String, MacosLibraryGrant>{};

  Future<String?> chooseLibrary() async {
    final grant = await _access.chooseLibrary();
    if (grant == null) return null;
    final previous = _libraries[grant.path];
    if (previous != null) {
      await grant.close();
    } else {
      _libraries[grant.path] = grant;
    }
    return grant.path;
  }

  @override
  Future<StorageBinding> prepareLibrary(String root) async {
    final grant = _libraries[root];
    if (grant == null)
      throw StateError('Choose the notes folder to grant access.');
    StorageBinding? binding;
    try {
      binding = await super.prepareLibrary(root);
      // Native storage keeps bookmarks by accepted path. If the subsequent
      // settings commit fails, the previous folder's bookmark is still intact.
      await grant.accept();
      return binding;
    } catch (_) {
      await super.releaseLibrary(binding ?? StorageBinding(root, 0));
      await grant.close();
      _libraries.remove(root);
      rethrow;
    }
  }

  @override
  Future<LibraryWatch> openLibraryWatch(StorageBinding binding) =>
      NativeLibraryWatch.open(
        binding,
        verify: _settings.verifyStoragePath,
        watchAncestors: false,
      );

  @override
  Future<void> releaseLibrary(StorageBinding binding) async {
    await super.releaseLibrary(binding);
    final grant = _libraries[binding.root];
    if (grant != null) {
      await grant.close();
      _libraries.remove(binding.root);
    }
  }

  Future<FilePickerResult?> _pick({
    required bool multiple,
    List<String>? extensions,
  }) async {
    final grants = await _access.chooseInputs(
      allowMultiple: multiple,
      extensions: extensions,
    );
    if (grants == null) return null;
    return FilePickerResult(await _retain(grants));
  }

  Future<List<PlatformFile>> retainDroppedInputs(List<String> paths) async =>
      _retain(await _access.retainDroppedInputs(paths));

  Future<List<PlatformFile>> _retain(List<MacosInputGrant> grants) async {
    final files = <PlatformFile>[];
    final admitted = <String>{};
    for (final grant in grants) {
      if (!admitted.add(grant.path)) {
        await grant.close();
        continue;
      }
      (_inputs[grant.path] ??= []).add(grant);
      files.add(
        PlatformFile(path: grant.path, name: grant.name, size: grant.length),
      );
    }
    return files;
  }

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) =>
      _pick(multiple: false, extensions: allowedExtensions);

  @override
  Future<FilePickerResult?> pickAttachments() => _pick(multiple: true);

  @override
  Future<List<String>> getRecentFiles() async => (await super.getRecentFiles())
      // Finder bookkeeping is not a note envelope. Exclude it before UID
      // resolution so binary metadata never enters owned note reads.
      .where((name) => name != '.DS_Store' && !name.startsWith('._'))
      .toList();

  @override
  String? sourceDisplayName(String path) => _inputs[path]?.first.name;

  @override
  Future<void> releasePickedSource(String path) async {
    final scopes = _inputs[path];
    if (scopes == null || scopes.isEmpty) return;
    // Keep failed releases for a retry. Access is never dropped merely because
    // the chooser/dialog closed or a different note became selected.
    await scopes.first.close();
    scopes.removeAt(0);
    if (scopes.isEmpty) _inputs.remove(path);
  }

  @override
  Future<void> closePersistence() async {
    await super.closePersistence();
    for (final path in _inputs.keys.toList()) {
      while (_inputs.containsKey(path)) {
        await releasePickedSource(path);
      }
    }
    for (final grant in _libraries.values.toList()) {
      await grant.close();
      _libraries.remove(grant.path);
    }
  }
}
