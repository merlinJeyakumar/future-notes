import 'package:flutter/material.dart';

enum ShareFormat { pdf, text, html }

class ShareOptionsDialog extends StatefulWidget {
  const ShareOptionsDialog({super.key});

  @override
  State<ShareOptionsDialog> createState() => _ShareOptionsDialogState();
}

class _ShareOptionsDialogState extends State<ShareOptionsDialog> {
  ShareFormat _selectedFormat = ShareFormat.pdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use app theme colors safely
    // Assuming custom theme extension or standard scheme usage from codebase context
    // Defaulting to standard scheme for safety if custom extensions aren't fully known here
    // but based on previous files, theme usage is consistent.

    return AlertDialog(
      backgroundColor: Theme.of(
        context,
      ).cardColor, // fallback if appSurface not available
      title: Text('Share Note', style: TextStyle(color: theme.iconTheme.color)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            context,
            format: ShareFormat.pdf,
            title: 'PDF Document (.pdf)',
            icon: Icons.picture_as_pdf,
          ),
          const SizedBox(height: 8),
          _buildOption(
            context,
            format: ShareFormat.text,
            title: 'Plain Text (.txt)',
            icon: Icons.description,
          ),
          const SizedBox(height: 8),
          _buildOption(
            context,
            format: ShareFormat.html,
            title: 'HTML Document (.html)',
            icon: Icons.html,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedFormat),
          child: const Text('Share'),
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required ShareFormat format,
    required String title,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedFormat == format;

    return InkWell(
      onTap: () => setState(() => _selectedFormat = format),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.dividerColor.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Radio<ShareFormat>(
              value: format,
              groupValue: _selectedFormat,
              onChanged: (val) => setState(() => _selectedFormat = val!),
              activeColor: theme.colorScheme.primary,
            ),
            Icon(icon, color: theme.iconTheme.color, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
