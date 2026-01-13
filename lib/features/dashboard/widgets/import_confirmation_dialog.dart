import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

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
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.appSurface,
      title: Text("Import File", style: TextStyle(color: theme.appTextPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "File: $fileName",
            style: TextStyle(color: theme.appTextSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            "Type: $fileType",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.appTextPrimary,
            ),
          ),
          if (previewInfo != null) ...[
            const SizedBox(height: 12),
            Text(
              "Preview Details:",
              style: TextStyle(color: theme.appSubtleGray),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.appSurfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                previewInfo!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.appTextSecondary,
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
          child: Text(
            "Cancel",
            style: TextStyle(color: theme.appTextSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Import"),
        ),
      ],
    );
  }
}
