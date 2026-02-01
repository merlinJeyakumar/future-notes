import 'package:flutter/material.dart';

import '../models/note_model.dart';
import 'file_details_dialog.dart';
import '../../../core/theme/app_theme.dart';

class Sidebar extends StatelessWidget {
  final List<RecentFile> recentFiles;

  final Function(String) onFileSelected;
  final Function(RecentFile) onOpenFolder;
  final Function(RecentFile) onDelete;
  final VoidCallback onNewNote;
  final VoidCallback? onImportNote;
  final VoidCallback? onSettings;
  final VoidCallback? onRefresh;
  final Function(String)? onSearchChanged;
  final Function(RecentFile)? onExportPack;

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 280,
      color: theme.appSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Area
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(Icons.inbox, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Notes',
                  style: TextStyle(
                    color: theme.appTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // New Note & Settings Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onNewNote,
                      icon: const Icon(Icons.add),
                      label: const Text('New Note'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (onSettings != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.appSurfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.appBorder),
                      ),
                      child: IconButton(
                        onPressed: onSettings,
                        icon: Icon(
                          Icons.settings,
                          color: theme.appTextSecondary,
                        ),
                        tooltip: 'Settings',
                        splashRadius: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Import Note button
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onImportNote,
                icon: const Icon(Icons.file_upload),
                label: const Text('Import Note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.appTextSecondary,
                  side: BorderSide(color: theme.appBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.appSurfaceVariant,
                hintText: 'Search...',
                hintStyle: TextStyle(color: theme.appSubtleGray),
                prefixIcon: Icon(Icons.search, color: theme.appSubtleGray),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.appBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.appBorder),
                ),
              ),
              style: TextStyle(color: theme.appTextPrimary),
              onChanged: onSearchChanged,
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(context, 'FILES'),
          Expanded(
            child: recentFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          color: theme.appSubtleGray.withOpacity(0.5),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No files found',
                          style: TextStyle(
                            color: theme.appSubtleGray.withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: recentFiles.length,
                    itemBuilder: (context, index) {
                      final file = recentFiles[index];
                      return ListTile(
                        leading: Icon(
                          Icons.description,
                          color: theme.appTextSecondary,
                          size: 20,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.title,
                                style: TextStyle(color: theme.appTextSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (file.isLocked)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.lock_outline,
                                  color: Colors.amberAccent,
                                  size: 14,
                                ),
                              ),
                          ],
                        ),
                        onTap: () => onFileSelected(file.path),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        dense: true,
                        trailing: IconButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: theme.appTextSecondary,
                            size: 20,
                          ),
                          onPressed: () => _showFileDetails(context, file),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.appSubtleGray,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          if (onRefresh != null)
            SizedBox(
              height: 24,
              width: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.refresh, color: theme.appSubtleGray, size: 16),
                onPressed: onRefresh,
                tooltip: 'Refresh',
              ),
            ),
        ],
      ),
    );
  }

  void _showFileDetails(BuildContext context, RecentFile file) {
    showDialog(
      context: context,
      builder: (context) {
        return FileDetailsDialog(
          file: file,
          onOpenFolder: onOpenFolder,
          onDelete: onDelete,
          onExportPack: onExportPack,
        );
      },
    );
  }
}
