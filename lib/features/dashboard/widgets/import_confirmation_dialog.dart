import 'package:flutter/material.dart';

class ImportConfirmationDialog extends StatelessWidget {
  final String fileName;
  final String fileType;
  final String? previewInfo;

  const ImportConfirmationDialog({
    super.key,
    required this.fileName,
    required this.fileType,
    this.previewInfo,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Import File"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("File: $fileName"),
          const SizedBox(height: 8),
          Text(
            "Type: $fileType",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (previewInfo != null) ...[
            const SizedBox(height: 12),
            const Text(
              "Preview Details:",
              style: TextStyle(color: Colors.grey),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                previewInfo!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.black87,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Import"),
        ),
      ],
    );
  }
}
