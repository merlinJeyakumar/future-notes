import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../../../core/theme/app_dialog.dart';
import '../../../core/theme/app_motion.dart';
import 'note_activity.dart';
import '../models/note_list_ui_state.dart';
import '../models/note_model.dart';

enum _NoteAction { info, export, delete }

/// A phone/tablet notes browser. The desktop Sidebar is a separate widget.
class MobileNotesList extends StatelessWidget {
  const MobileNotesList({
    super.key,
    required this.listState,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onFileSelected,
    required this.onNewNote,
    required this.onImport,
    required this.onNotifications,
    this.notificationCount = 0,
    this.activity,
    required this.onSettings,
    required this.onRefresh,
    required this.onRetrySearch,
    required this.onDelete,
    required this.onExport,
  });
  final NoteListUiState listState;
  final ValueListenable<Map<String, NoteActivity>>? activity;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<RecentFile> onFileSelected;
  final VoidCallback onNewNote,
      onImport,
      onNotifications,
      onSettings,
      onRefresh,
      onRetrySearch;
  final ValueChanged<RecentFile> onDelete, onExport;
  final int notificationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onNewNote,
        icon: const Icon(Icons.add),
        label: const Text('New note'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Future Notes',
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'App settings',
                    onPressed: onSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  if (notificationCount > 0)
                    IconButton(
                      tooltip: '$notificationCount job notifications',
                      onPressed: onNotifications,
                      icon: Badge.count(
                        count: notificationCount,
                        child: const Icon(Icons.notifications_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: listState.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Text(
                        listState.query.isEmpty ? 'Notes' : 'Results',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        label:
                            '${listState.files.length} ${listState.query.isEmpty ? 'notes' : 'results'}',
                        excludeSemantics: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .06,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${listState.files.length}',
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: onImport,
                        icon: const Icon(Icons.file_upload_outlined, size: 20),
                        label: const Text('Import'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(88, 48),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh notes',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                if (listState.updating)
                  const Positioned(
                    left: 16,
                    right: 16,
                    bottom: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
          if (listState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      listState.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: listState.query.isEmpty
                        ? onRefresh
                        : onRetrySearch,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: listState.files.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        listState.updating
                            ? 'Loading notes…'
                            : listState.error != null
                            ? 'Notes unavailable'
                            : listState.query.isEmpty
                            ? 'Create your first note'
                            : 'No matching notes',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey('mobile-notes-list'),
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                    itemCount: listState.files.length,
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      final index = listState.files.indexWhere(
                        (file) => file.fullPath == key.value,
                      );
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (context, index) {
                      final file = listState.files[index];
                      final selected =
                          file.fullPath == listState.selectedContentPath;
                      final lock = selected
                          ? listState.selectedLockState
                          : file.isLocked
                          ? listState.unlockedContentPaths.contains(
                                  file.fullPath,
                                )
                                ? NoteLockState.unlocked
                                : NoteLockState.locked
                          : NoteLockState.unprotected;
                      return Padding(
                        key: ValueKey(file.fullPath),
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          minVerticalPadding: 12,
                          contentPadding: const EdgeInsets.only(
                            left: 12,
                            right: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selected: selected,
                          selectedTileColor: theme.colorScheme.primary
                              .withValues(alpha: .12),
                          leading: SizedBox(
                            width: 36,
                            height: 40,
                            child: _activityIcon(
                              context,
                              file.path,
                              switch (lock) {
                                NoteLockState.locked => Icons.lock_rounded,
                                NoteLockState.unlocked =>
                                  Icons.lock_open_rounded,
                                _ => Icons.description_outlined,
                              },
                            ),
                          ),
                          title: Text(
                            file.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _subtitle(file),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          onTap: () => onFileSelected(file),
                          trailing: PopupMenuButton<_NoteAction>(
                            tooltip: 'More actions for ${file.title}',
                            onSelected: (action) {
                              switch (action) {
                                case _NoteAction.info:
                                  _info(context, file);
                                case _NoteAction.export:
                                  onExport(file);
                                case _NoteAction.delete:
                                  onDelete(file);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: _NoteAction.info,
                                child: Text('Note information'),
                              ),
                              PopupMenuItem(
                                value: _NoteAction.export,
                                child: Text('Export'),
                              ),
                              PopupMenuItem(
                                value: _NoteAction.delete,
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _activityIcon(BuildContext context, String note, IconData icon) {
    final source = activity;
    if (source == null) return Icon(icon, size: 22);
    return ValueListenableBuilder<Map<String, NoteActivity>>(
      valueListenable: source,
      builder: (context, activities, _) {
        final count = activities[note]?.activeJobs ?? 0;
        if (count == 0) return Icon(icon, size: 22);
        final message =
            '$count attachment operation${count == 1 ? '' : 's'} in progress';
        return Semantics(
          label: message,
          child: Tooltip(
            message: message,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 22),
                if (AppMotion.reduced(context))
                  Align(
                    alignment: Alignment.bottomRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.sync,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                else
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
              ],
            ),
          ),
        );
      },
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
        '${two(date.day)}/${two(date.month)}/${two(date.year % 100)} ${two(date.hour)}:${two(date.minute)}',
      if (suffix != null) suffix,
    ].join(' • ');
  }

  void _info(BuildContext context, RecentFile file) => showAppDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note information'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(file.title),
          const SizedBox(height: 12),
          Text(_subtitle(file)),
          if (file.noteId != null) ...[
            const SizedBox(height: 12),
            SelectableText('ID: ${file.noteId}'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
