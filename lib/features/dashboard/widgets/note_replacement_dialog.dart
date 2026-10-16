import '../../../core/theme/app_tooltip.dart';
import 'package:flutter/material.dart';

import '../models/note_import.dart';

/// The decision state can be hosted by the import dialog or shown on its own.
class NoteReplacementDialog extends StatelessWidget {
  const NoteReplacementDialog({
    super.key,
    required this.conflict,
    this.onDecision,
    this.fileName,
  });
  final NoteImportConflict conflict;
  final ValueChanged<NoteImportDecision>? onDecision;
  final String? fileName;

  void _choose(BuildContext context, NoteImportDecision decision) {
    if (onDecision != null) {
      onDecision!(decision);
    } else {
      Navigator.pop(context, decision);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import note',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              if (fileName != null) ...[
                const SizedBox(height: 8),
                AppTooltip(
                  message: fileName!,
                  child: Text(fileName!, softWrap: true),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'This note already exists',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                conflict.identical
                    ? 'The imported version is identical.'
                    : 'The imported version has different content.',
              ),
              const SizedBox(height: 12),
              Text(
                conflict.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              _choice(
                context,
                NoteImportDecision.duplicate,
                Icons.copy_outlined,
                'Duplicate',
                'Create a separate note with a new ID.',
              ),
              const SizedBox(height: 8),
              _choice(
                context,
                NoteImportDecision.replace,
                Icons.restore_outlined,
                'Back up & Replace',
                'Keep a verified recovery copy, then replace the existing note.',
              ),
              const SizedBox(height: 8),
              _choice(
                context,
                NoteImportDecision.ignore,
                Icons.block_outlined,
                'Ignore',
                'Keep the existing note unchanged.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(
    BuildContext context,
    NoteImportDecision decision,
    IconData icon,
    String label,
    String detail,
  ) => OutlinedButton(
    autofocus: decision == NoteImportDecision.ignore,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    onPressed: () => _choose(context, decision),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}
