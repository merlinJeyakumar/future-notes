import 'note_model.dart';
import '../../../core/storage/note_reference.dart';
import 'note_envelope.dart';
export 'note_envelope.dart' show NoteEnvelopeKind;

enum DraftAccess { editable, locked, unsupported, corrupt, deleted }

enum DraftField { body, title, attachments, protection }

/// An immutable view of editor ownership and acknowledged persistence.
class DraftSession {
  DraftSession({
    required this.generation,
    this.access = DraftAccess.editable,
    this.editRevision = 0,
    this.persistedRevision,
    this.credentialGeneration = 0,
    Set<DraftField> dirtyFields = const {},
  }) : dirtyFields = Set.unmodifiable(dirtyFields);

  final int generation;
  final DraftAccess access;
  final int editRevision;
  final int? persistedRevision;
  final int credentialGeneration;
  final Set<DraftField> dirtyFields;

  bool get canWrite => access == DraftAccess.editable;
  bool get isPersisted => persistedRevision != null;
  bool get isDirty => dirtyFields.isNotEmpty;

  DraftSession edited(DraftField field) => DraftSession(
    generation: generation,
    access: access,
    editRevision: editRevision + 1,
    persistedRevision: persistedRevision,
    credentialGeneration:
        credentialGeneration + (field == DraftField.protection ? 1 : 0),
    dirtyFields: {...dirtyFields, field},
  );

  DraftSession acknowledged(int revision) => DraftSession(
    generation: generation,
    access: access,
    editRevision: editRevision,
    persistedRevision: revision,
    credentialGeneration: credentialGeneration,
    dirtyFields: revision == editRevision ? const {} : dirtyFields,
  );
}

/// Captured synchronously before enqueueing any asynchronous save work.
/// Expected storage revisions and recoverable commits follow in Stage 2.
class NoteSnapshot {
  NoteSnapshot({
    required this.sessionGeneration,
    required this.editRevision,
    required this.credentialGeneration,
    required this.fileName,
    required this.reference,
    required this.noteId,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.password,
    required this.envelopeKind,
    required Map<String, dynamic> metadata,
    required List<AttachmentModel> attachments,
    required this.reuseStoredBody,
    required this.attachmentsChanged,
  }) : metadata = _freezeMap(metadata),
       attachments = List.unmodifiable(attachments);

  final int sessionGeneration;
  final int editRevision;
  final int credentialGeneration;
  final String? fileName;
  final NoteReference? reference;
  final String noteId;
  final String title;
  final String body;
  final int timestamp;
  final String? password;
  final NoteEnvelopeKind envelopeKind;
  final Map<String, dynamic> metadata;
  final List<AttachmentModel> attachments;
  final bool reuseStoredBody;
  final bool attachmentsChanged;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    Map.unmodifiable(value.map((key, value) => MapEntry(key, _freeze(value))));

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) return _freezeMap(value);
  if (value is List) return List.unmodifiable(value.map(_freeze));
  return value;
}
