import 'note_model.dart';

enum NoteEnvelopeKind { appEncrypted, legacyJson }

/// A validated envelope with its original metadata representation retained.
class DecodedNote {
  DecodedNote(this.note, Map<String, dynamic> metadata, this.kind)
    : metadata = _freezeMap(metadata);

  final NoteModel note;
  final Map<String, dynamic> metadata;
  final NoteEnvelopeKind kind;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    Map.unmodifiable(value.map((key, value) => MapEntry(key, _freeze(value))));

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) return _freezeMap(value);
  if (value is List) return List.unmodifiable(value.map(_freeze));
  return value;
}
