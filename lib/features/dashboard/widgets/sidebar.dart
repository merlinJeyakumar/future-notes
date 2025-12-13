import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';

class Sidebar extends StatelessWidget {
  final List<RecentFile> recentFiles;

  final Function(String) onFileSelected;
  final Function(RecentFile) onOpenFolder;
  final Function(RecentFile) onDelete;
  final VoidCallback onNewNote;

  const Sidebar({
    super.key,
    this.recentFiles = const [],
    required this.onFileSelected,
    required this.onOpenFolder,
    required this.onDelete,
    required this.onNewNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: const Color(0xFF161E2D), // Dark sidebar background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Area
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(Icons.inbox, color: Colors.blueAccent, size: 32),
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

          // New Note Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
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
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader('RECENT'),
          Expanded(
            child: ListView.builder(
              itemCount: recentFiles.length,
              itemBuilder: (context, index) {
                final file = recentFiles[index];
                return ListTile(
                  leading: const Icon(
                    Icons.description,
                    color: Colors.white70,
                    size: 20,
                  ),
                  title: Text(
                    file.title,
                    style: const TextStyle(color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onFileSelected(file.path),

                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
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
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showFileDetails(BuildContext context, RecentFile file) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161E2D),
          title: Text(
            file.title,
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCopiableDetailRow(context, "File Name:", file.path),
              _buildCopiableDetailRow(context, "File Path:", file.fullPath),
              _buildDetailRow(
                "Created:",
                file.created?.toString().split('.').first ?? "Unknown",
              ),
              _buildDetailRow(
                "Modified:",
                file.modified?.toString().split('.').first ?? "Unknown",
              ),
              _buildDetailRow("Locked:", file.isLocked ? "Yes" : "No"),
              _buildDetailRow("Encrypted:", "AES-256 (App Key)"),
              _buildDetailRow(
                "Size:",
                file.sizeBytes != null ? "${file.sizeBytes} B" : "Unknown",
              ),
              const SizedBox(height: 20),

              Divider(color: Colors.grey[700]),

              ListTile(
                leading: const Icon(
                  Icons.folder_open,
                  color: Colors.blueAccent,
                ),
                title: const Text(
                  "Show Folder",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  onOpenFolder(file);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context); // Close details dialog first
                  _showDeleteConfirmation(context, file);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, RecentFile file) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161E2D),
          title: const Text(
            "Delete File?",
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            "Are you sure you want to delete '${file.title}'? This cannot be undone.",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text("Delete"),
              onPressed: () {
                onDelete(file);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildCopiableDetailRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(Icons.copy, size: 16, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }
}
