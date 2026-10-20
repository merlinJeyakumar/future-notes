import '../../../core/storage/note_reference.dart';
import 'note_envelope.dart';

class SharedAttachmentPasswordRequired implements Exception {
  const SharedAttachmentPasswordRequired();
}

/// Captured mobile destination. Credentials are memory-only, never serialized.
class SharedAttachmentTarget {
  const SharedAttachmentTarget(this.reference, this.decoded, this.password);
  final NoteReference reference;
  final DecodedNote decoded;
  final String? password;
}
