import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';
import 'file_details_dialog.dart';

class Sidebar extends StatelessWidget {
  final List<RecentFile> recentFiles;

  final Function(String) onFileSelected;
  final Function(RecentFile) onOpenFolder;
  final Function(RecentFile) onDelete;
  final VoidCallback onNewNote;
  final VoidCallback? onImportNote;
  final VoidCallback? onSettings;
  final VoidCallback? onRefresh; // Added callback
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
    return Container(
      width: 280,
      color: const Color(0xFF161E2D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Area
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                const Icon(Icons.inbox, color: Colors.blueAccent, size: 32),
                const SizedBox(width: 12),
                const Text(
                  'Notes',
                  style: TextStyle(
                    color: Colors.white,
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
                        backgroundColor: Colors.blueAccent,
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: IconButton(
                        onPressed: onSettings,
                        icon: const Icon(Icons.settings, color: Colors.white70),
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
          if (Platform.isAndroid || Platform.isIOS) // Only show on mobile
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onImportNote,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import Note'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
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
                fillColor: const Color(0xFF1E293B),
                hintText: 'Search...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: onSearchChanged,
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader('FILES'),
          Expanded(
            child: recentFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off,
                          color: Colors.white24,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No files found',
                          style: TextStyle(color: Colors.white24, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: recentFiles.length,
                    itemBuilder: (context, index) {
                      final file = recentFiles[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.description,
                          color: Colors.white70,
                          size: 20,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.title,
                                style: const TextStyle(color: Colors.white70),
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
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white70,
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
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
                icon: const Icon(Icons.refresh, color: Colors.grey, size: 16),
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
