import 'package:flutter/material.dart';
import '../../../core/operations/operation_result.dart';
import '../models/attachment_job.dart';
import '../models/note_import.dart';
import '../widgets/attachment_presentation.dart' show formatAttachmentBytes;

/// Mobile presentation only. The shared import dialog owns jobs and decisions.
class MobileImportDialog extends StatelessWidget {
  const MobileImportDialog({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class MobileImportSetupDialog extends StatefulWidget {
  const MobileImportSetupDialog({
    super.key,
    required this.fileName,
    required this.size,
    required this.fileType,
    required this.isPackage,
    required this.passwordRequired,
    this.previewInfo,
  });
  final String fileName, fileType;
  final int size;
  final bool isPackage, passwordRequired;
  final String? previewInfo;
  @override
  State<MobileImportSetupDialog> createState() =>
      _MobileImportSetupDialogState();
}

class _MobileImportSetupDialogState extends State<MobileImportSetupDialog> {
  final _password = TextEditingController();
  bool _optionalPassword = false, _reveal = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.passwordRequired && _password.text.isEmpty) {
      setState(() => _error = 'Enter the package password.');
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => MobileImportDialog(
    title: 'Import note',
    children: [
      _SourceSummary(
        fileName: widget.fileName,
        subtitle:
            '${widget.isPackage ? 'Note package' : widget.fileType} · ${formatAttachmentBytes(widget.size)}',
      ),
      const SizedBox(height: 16),
      Text(
        'Add this note to your library.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (widget.previewInfo case final info?)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Note details'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(info, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      if (widget.isPackage && !widget.passwordRequired)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _optionalPassword,
          onChanged: (value) => setState(() {
            _optionalPassword = value!;
            if (!value) _password.clear();
          }),
          title: const Text('Package has a password'),
        ),
      if (widget.passwordRequired || _optionalPassword) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: !_reveal,
          autocorrect: false,
          enableSuggestions: false,
          autofocus: widget.passwordRequired,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Package password',
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: _reveal ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _reveal = !_reveal),
              icon: Icon(
                _reveal
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 12,
        overflowSpacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import'),
          ),
        ],
      ),
    ],
  );
}

class _SourceSummary extends StatelessWidget {
  const _SourceSummary({required this.fileName, this.subtitle});
  final String fileName;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.description_outlined,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                style: theme.textTheme.titleSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Widget mobileImportConflict(
  BuildContext context,
  NoteImportConflict conflict,
  ValueChanged<NoteImportDecision> choose,
) {
  final theme = Theme.of(context);
  final id = conflict.reference.modelId;
  return MobileImportDialog(
    title: 'Note already exists',
    children: [
      _SourceSummary(
        fileName: conflict.title,
        subtitle: id == null
            ? 'Matching note ID'
            : 'ID ${id.substring(0, id.length < 8 ? id.length : 8)}',
      ),
      const SizedBox(height: 16),
      Text(
        'Choose how to import this note.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      for (final option in [
        (
          NoteImportDecision.duplicate,
          Icons.copy_outlined,
          'Duplicate',
          'Create a separate note with a new ID.',
        ),
        (
          NoteImportDecision.replace,
          Icons.restore_page_outlined,
          'Back up & Replace',
          'Keep a recovery copy, then replace the existing note.',
        ),
        (
          NoteImportDecision.ignore,
          Icons.skip_next_outlined,
          'Ignore',
          'Keep the existing note unchanged.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => choose(option.$1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(option.$2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.$3, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(option.$4, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

Widget mobileImportBody(
  BuildContext context,
  AttachmentJobSnapshot? progress,
  OperationResult<NoteImportResult>? result,
  bool cancelling,
  VoidCallback cancel,
  VoidCallback close, {
  required String fileName,
}) {
  final theme = Theme.of(context);
  final finishing = progress?.phase == AttachmentJobPhase.finalizing;
  final cancelled = result?.outcome == OperationOutcome.cancelled;
  final title = result == null
      ? 'Import note'
      : result.isSuccess
      ? switch (result.value!.disposition) {
          NoteImportDisposition.created => 'Note imported',
          NoteImportDisposition.duplicated => 'Duplicate created',
          NoteImportDisposition.replaced => 'Note replaced',
          NoteImportDisposition.ignored => 'Import ignored',
        }
      : cancelled
      ? 'Import cancelled'
      : 'Import needs attention';
  final file = progress?.fileProgress;
  return MobileImportDialog(
    title: title,
    children: [
      _SourceSummary(fileName: fileName),
      const SizedBox(height: 24),
      if (result == null) ...[
        Text(
          cancelling
              ? 'Cancelling import…'
              : progress?.detail ?? 'Preparing import…',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (file != null && file.total > 0) ...[
          _ImportMetric(
            label: 'Current file',
            bytes: file.bytes,
            total: file.total,
          ),
          const SizedBox(height: 20),
          _ImportMetric(
            label: 'Overall saving',
            bytes: file.overallBytes,
            total: file.overallTotal,
          ),
        ] else
          _ImportMetric(
            bytes: progress?.bytes ?? 0,
            total: file != null ? 0 : progress?.total ?? 0,
          ),
      ] else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              result.isSuccess
                  ? Icons.check_circle_outline
                  : cancelled
                  ? Icons.cancel_outlined
                  : Icons.error_outline,
              color: result.isSuccess || cancelled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.isSuccess
                    ? switch (result.value!.disposition) {
                        NoteImportDisposition.created =>
                          'The note is ready in your library.',
                        NoteImportDisposition.duplicated =>
                          'A separate note was created. The existing note is unchanged.',
                        NoteImportDisposition.replaced =>
                          'The note was replaced. Its recovery copy was retained.',
                        NoteImportDisposition.ignored =>
                          'The existing note is unchanged.',
                      }
                    : result.message ?? 'Import did not complete.',
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerRight,
        child: result != null
            ? FilledButton(onPressed: close, child: const Text('Close'))
            : TextButton(
                onPressed: finishing || cancelling ? null : cancel,
                child: Text(
                  finishing
                      ? 'Finishing…'
                      : cancelling
                      ? 'Cancelling…'
                      : 'Cancel import',
                ),
              ),
      ),
    ],
  );
}

class _ImportMetric extends StatelessWidget {
  const _ImportMetric({this.label, required this.bytes, required this.total});
  final String? label;
  final int bytes, total;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null) ...[
        Text(label!, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
      ],
      LinearProgressIndicator(
        value: total > 0 ? (bytes / total).clamp(0.0, 1.0) : null,
        borderRadius: BorderRadius.circular(4),
        minHeight: 5,
      ),
      if (total > 0) ...[
        const SizedBox(height: 8),
        Text(
          '${formatAttachmentBytes(bytes)} / ${formatAttachmentBytes(total)} · ${((bytes / total).clamp(0.0, 1.0) * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}
