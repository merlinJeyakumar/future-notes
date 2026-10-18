import '../../../core/storage/note_reference.dart';

enum NoteImportDisposition { created, duplicated, ignored, replaced }

enum NoteImportDecision { duplicate, replace, ignore }

class NoteImportResult {
  const NoteImportResult(this.disposition, this.fileName);
  final NoteImportDisposition disposition;
  final String fileName;
}

class NoteImportConflict {
  const NoteImportConflict(
    this.reference,
    this.title,
    this.isLocked, {
    this.identical,
  });
  final NoteReference reference;
  final String title;
  final bool isLocked;

  /// Null means the conflict was found by identity without comparing payloads.
  final bool? identical;
}

typedef ResolveNoteImportConflict =
    Future<NoteImportDecision> Function(NoteImportConflict note);
