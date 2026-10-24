import 'dart:typed_data';

/// Optional platform capability. Desktop writers do not generate thumbnails.
abstract interface class AttachmentThumbnailSource {
  bool get supportsAttachmentThumbnails;
  Future<Uint8List?> thumbnailFromPickedSource(String path, String fileName);
  Future<Uint8List?> thumbnailFromCachedFile(String path, String fileName);
}
