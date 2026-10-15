import 'note_model.dart';

enum NoteLockState { unprotected, locked, unlocked }

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
    this.selectedLockState,
    this.unlockedContentPaths = const {},
    this.libraryEpoch = 0,
  });
  final List<RecentFile> files;
  final String query;
  final String displayedQuery;
  final bool isScanning;
  final bool isFiltering;
  final String? error;
  final String? selectedContentPath;
  final NoteLockState? selectedLockState;
  final Set<String> unlockedContentPaths;
  final int libraryEpoch;
  bool get updating => isScanning || isFiltering;
}
