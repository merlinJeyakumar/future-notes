import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';

class FileDetailsDialog extends StatelessWidget {
  final RecentFile file;
  final Function(RecentFile) onOpenFolder;
  final Function(RecentFile) onDelete;
  final Function(RecentFile)? onExportPack;

  const FileDetailsDialog({
    super.key,
    required this.file,
    required this.onOpenFolder,
    required this.onDelete,
    this.onExportPack,
  });

  @override
  Widget build(BuildContext context) {
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
          _buildDetailRow(
            "Encrypted:",
            file.isLocked ? "User Encrypted" : "AES-256 (App Key)",
          ),
          _buildDetailRow(
            "Size:",
            file.sizeBytes != null ? "${file.sizeBytes} B" : "Unknown",
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey[700]),
          ListTile(
            leading: const Icon(Icons.folder_open, color: Colors.blueAccent),
            title: const Text(
              "Show Folder",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              if (Platform.isAndroid || Platform.isIOS) {
                Navigator.pop(context);
                _showMobileFolderInfo(context, file);
              } else {
                onOpenFolder(file);
                Navigator.pop(context);
              }
            },
          ),
          // Export Note Package - available on all platforms
          ListTile(
            leading: const Icon(Icons.share, color: Colors.greenAccent),
            title: const Text(
              "Export Note Package",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              "Export with attachments",
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            onTap: () {
              Navigator.pop(context);
              if (onExportPack != null) {
                onExportPack!(file);
              }
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

  void _showMobileFolderInfo(BuildContext context, RecentFile file) {
    String folderPath = "Unknown";
    try {
      folderPath = File(file.fullPath).parent.path;
    } catch (e) {
      folderPath = file.path;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161E2D),
          title: const Text(
            "Folder Location",
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "File is located at:",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        folderPath,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.blueAccent),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: folderPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Path copied to clipboard'),
                          ),
                        );
                      },
                      tooltip: 'Copy path',
                    ),
                  ],
                ),
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
}
