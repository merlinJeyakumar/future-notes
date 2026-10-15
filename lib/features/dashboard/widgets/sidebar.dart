import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/note_model.dart';
import '../models/note_list_ui_state.dart';
import 'file_details_dialog.dart';
import '../../../core/theme/app_theme.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    this.recentFiles = const [],
    required this.onFileSelected,
    required this.onOpenFolder,
    required this.onDelete,
    required this.onNewNote,
    this.onImportNote,
    this.onSettings,
    this.onRefresh,
    this.onSearchChanged,
    this.onExportPack,
    this.listState,
    this.searchController,
    this.searchFocusNode,
    this.onRecentFileSelected,
    this.onRetrySearch,
  });
  final List<RecentFile> recentFiles;
  final ValueChanged<String> onFileSelected;
  final ValueChanged<RecentFile> onOpenFolder;
  final ValueChanged<RecentFile> onDelete;
  final VoidCallback onNewNote;
  final VoidCallback? onImportNote;
  final VoidCallback? onSettings;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<RecentFile>? onExportPack;
  final NoteListUiState? listState;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<RecentFile>? onRecentFileSelected;
  final VoidCallback? onRetrySearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = listState;
    final files = state?.files ?? recentFiles;
    return Container(
      width: 280,
      color: theme.appSidebar,
      child: CustomScrollView(
        key: const PageStorageKey('notes-sidebar'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inbox, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Notes',
                          style: TextStyle(
                            fontSize: 15.552,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (onSettings != null)
                        IconButton(
                          tooltip: 'App settings',
                          onPressed: onSettings,
                          icon: const Icon(Icons.settings_outlined),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onNewNote,
                    icon: const Icon(Icons.add),
                    label: const Text('New Note'),
                  ),
                  TextButton.icon(
                    onPressed: onImportNote,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import Note'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    focusNode: searchFocusNode,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      labelText: 'Search notes',
                      hintText: 'Search…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon:
                          (state?.query.isNotEmpty ??
                              searchController?.text.isNotEmpty ??
                              false)
                          ? IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                searchController?.clear();
                                onSearchChanged?.call('');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('FILES')),
                      if (onRefresh != null)
                        IconButton(
                          tooltip: 'Refresh notes',
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  if (state?.updating ?? false) ...[
                    const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        state!.isFiltering ? 'Searching…' : 'Updating notes…',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                  if (state?.error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state!.error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        TextButton(
                          onPressed: state.query.isEmpty
                              ? onRefresh
                              : onRetrySearch,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (files.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    state?.updating == true
                        ? 'Loading notes…'
                        : state?.error != null
                        ? 'Notes unavailable'
                        : state?.query.isNotEmpty == true
                        ? 'No matching notes'
                        : 'No notes yet. Create a new note.',
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final subtitle = _subtitle(file);
                final rememberedUnlocked =
                    state?.unlockedContentPaths.contains(file.fullPath) ??
                    false;
                final selected =
                    state?.selectedContentPath != null &&
                    p.equals(state!.selectedContentPath!, file.fullPath);
                return ListTile(
                  key: ValueKey(file.fullPath),
                  selected: selected,
                  selectedTileColor: theme.colorScheme.primary.withValues(
                    alpha: .12,
                  ),
                  leading: Icon(switch (selected
                      ? state.selectedLockState
                      : null) {
                    NoteLockState.locked => Icons.lock_rounded,
                    NoteLockState.unlocked => Icons.lock_open_rounded,
                    NoteLockState.unprotected => Icons.description_outlined,
                    null =>
                      file.isLocked
                          ? rememberedUnlocked
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded
                          : Icons.description_outlined,
                  }),
                  title: Tooltip(
                    message: file.title,
                    child: Text(
                      file.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  subtitle: subtitle.isEmpty
                      ? null
                      : Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: theme.textTheme.bodySmall?.fontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () {
                    if (onRecentFileSelected != null) {
                      onRecentFileSelected!(file);
                    } else {
                      onFileSelected(file.path);
                    }
                  },
                  trailing: IconButton(
                    tooltip: 'More actions for ${file.title}',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => FileDetailsDialog(
                        file: file,
                        onOpenFolder: onOpenFolder,
                        onDelete: onDelete,
                        onExportPack: onExportPack,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _subtitle(RecentFile file) {
    final date = (file.modified ?? file.created)?.toLocal();
    final id = file.noteId;
    final suffix = id == null || id.isEmpty
        ? null
        : String.fromCharCodes(
            id.runes.toList().reversed.take(5).toList().reversed,
          );
    String two(int value) => value.toString().padLeft(2, '0');
    return [
      if (date != null)
        '${two(date.day)}/${two(date.month)}/${two(date.year % 100)} '
            '${two(date.hour)}:${two(date.minute)}',
      if (suffix != null) suffix,
    ].join(' • ');
  }
}
