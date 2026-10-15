import 'note_model.dart';

/// Immutable projection of discovery/search; scheduling remains in the VM.
class NoteListUiState {
  const NoteListUiState({
    this.files = const [],
    this.query = '',
    this.displayedQuery = '',
    this.isScanning = false,
    this.isFiltering = false,
    this.error,
    this.selectedContentPath,
    this.libraryEpoch = 0,
  });
  final List<RecentFile> files;
  final String query;
  final String displayedQuery;
  final bool isScanning;
  final bool isFiltering;
  final String? error;
  final String? selectedContentPath;
  final int libraryEpoch;
  bool get updating => isScanning || isFiltering;
}
