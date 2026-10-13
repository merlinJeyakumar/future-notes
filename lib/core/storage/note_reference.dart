import 'package:path/path.dart' as p;
import 'native_storage_primitives.dart';
import 'storage_owner_worker.dart';

enum NoteStorageFormat { folder, legacyFile }

class StorageBinding {
  StorageBinding(String root, this.generation)
    : root = p.normalize(p.absolute(root));

  final String root;
  final int generation;

  String child(String relative) {
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      throw ArgumentError('Storage identity must be library-relative.');
    }
    final target = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, target)) {
      throw ArgumentError('Storage identity must remain within its library.');
    }
    return target;
  }
}

/// The exact object resolved when a session is opened, independent of settings.
class NoteReference {
  NoteReference({
    required this.binding,
    required this.fileName,
    required this.format,
    required this.contentPath,
    required this.attachmentLocation,
    this.modelId,
    this.storageRevision,
    this.storageOwner,
  });

  final StorageBinding binding;
  final String fileName;
  final NoteStorageFormat format;
  final String contentPath;
  final String attachmentLocation;
  final String? modelId;
  final StorageRevision? storageRevision;
  final StorageOwnerRoot? storageOwner;

  NoteReference withStorageRevision(
    StorageRevision revision,
    StorageOwnerRoot owner,
  ) => NoteReference(
    binding: binding,
    fileName: fileName,
    format: format,
    contentPath: contentPath,
    attachmentLocation: attachmentLocation,
    modelId: modelId,
    storageRevision: revision,
    storageOwner: owner,
  );

  NoteReference withModelId(String id) {
    final legacyAttachments = binding.child('note_$id/attachments');
    return NoteReference(
      binding: binding,
      fileName: fileName,
      format: format,
      contentPath: contentPath,
      attachmentLocation: format == NoteStorageFormat.folder
          ? attachmentLocation
          : legacyAttachments,
      modelId: id,
      storageRevision: storageRevision,
      storageOwner: storageOwner,
    );
  }
}
