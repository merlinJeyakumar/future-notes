import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';
import '../../../core/theme/app_theme.dart';

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
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.appSurface,
      title: Text(
        file.title,
        style: TextStyle(color: theme.appTextPrimary),
        overflow: TextOverflow.ellipsis,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCopiableDetailRow(context, "File Name:", file.path),
          _buildCopiableDetailRow(context, "File Path:", file.fullPath),
          _buildDetailRow(
            context,
            "Note date:",
            file.created?.toString().split('.').first ?? "Unknown",
          ),
          _buildDetailRow(
            context,
            "File modified:",
            file.modified?.toString().split('.').first ?? "Unknown",
          ),
          _buildDetailRow(context, "Locked:", file.isLocked ? "Yes" : "No"),
          _buildDetailRow(
            context,
            "Encrypted:",
            file.isLocked ? "User Encrypted" : "AES-256 (App Key)",
          ),
          _buildDetailRow(
            context,
            "Size:",
            file.sizeBytes != null ? "${file.sizeBytes} B" : "Unknown",
          ),
          const SizedBox(height: 20),
          Divider(color: theme.appDivider),
          ListTile(
            leading: Icon(Icons.folder_open, color: theme.colorScheme.primary),
            title: Text(
              "Show Folder",
              style: TextStyle(color: theme.appTextPrimary),
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
            leading: Icon(Icons.share, color: theme.appAccent),
            title: Text(
              "Export Note Package",
              style: TextStyle(color: theme.appTextPrimary),
            ),
            subtitle: Text(
              "Export with attachments",
              style: TextStyle(color: theme.appTextSecondary, fontSize: 9.504),
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
          child: Text(
            "Close",
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: theme.appSubtleGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: theme.appTextSecondary)),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: theme.appSubtleGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: theme.appTextSecondary),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(Icons.copy, size: 16, color: theme.appSubtleGray),
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
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.appSurface,
          title: Text(
            "Folder Location",
            style: TextStyle(color: theme.appTextPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "File is located at:",
                style: TextStyle(color: theme.appTextSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.appBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.appBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        folderPath,
                        style: TextStyle(
                          color: theme.appTextPrimary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: theme.colorScheme.primary),
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
              child: Text(
                "Close",
                style: TextStyle(color: theme.colorScheme.primary),
              ),
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
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.appSurface,
          title: Text(
            "Delete File?",
            style: TextStyle(color: theme.appTextPrimary),
          ),
          content: Text(
            "Are you sure you want to delete '${file.title}'? This cannot be undone.",
            style: TextStyle(color: theme.appTextSecondary),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(color: theme.appTextSecondary),
              ),
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
