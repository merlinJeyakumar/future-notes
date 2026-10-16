import '../../../core/theme/app_tooltip.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/operations/operation_result.dart';
import '../models/attachment_job.dart';
import '../models/note_import.dart';
import 'note_replacement_dialog.dart';

typedef StartNoteImport =
    Future<OperationResult<NoteImportResult>> Function(
      ResolveNoteImportConflict resolveConflict,
    );

/// One route owns preparation, an explicit conflict decision and the result.
/// Progress is isolated here and never rebuilds the editor or attachment dock.
class NoteImportDialog extends StatefulWidget {
  const NoteImportDialog({
    super.key,
    required this.fileName,
    required this.jobs,
    required this.startImport,
    required this.cancelJob,
  });
  final String fileName;
  final ValueListenable<List<AttachmentJobState>> jobs;
  final StartNoteImport startImport;
  final Future<void> Function(String id) cancelJob;

  @override
  State<NoteImportDialog> createState() => _NoteImportDialogState();
}

class _NoteImportDialogState extends State<NoteImportDialog> {
  late final Set<String> _previousJobs;
  AttachmentJobState? _job;
  NoteImportConflict? _conflict;
  Completer<NoteImportDecision>? _decision;
  OperationResult<NoteImportResult>? _result;
  bool _cancelRequested = false;
  final _signalled = <String>{};

  @override
  void initState() {
    super.initState();
    _previousJobs = widget.jobs.value
        .map((job) => job.progress.value.id)
        .toSet();
    widget.jobs.addListener(_jobsChanged);
    unawaited(Future<void>.microtask(_run));
  }

  void _jobsChanged() {
    if (!mounted) return;
    final jobs = widget.jobs.value
        .where(
          (job) =>
              job.progress.value.operation == AttachmentJobOperation.import &&
              !_previousJobs.contains(job.progress.value.id),
        )
        .toList();
    if (jobs.isEmpty) return;
    if (!identical(_job, jobs.last)) {
      _job?.progress.removeListener(_jobProgressChanged);
      jobs.last.progress.addListener(_jobProgressChanged);
    }
    setState(() => _job = jobs.last);
    if (_cancelRequested) unawaited(_signalCancellation());
  }

  void _jobProgressChanged() {
    if (!mounted) return;
    final phase = _job?.progress.value.phase;
    if (phase != AttachmentJobPhase.cancelling &&
        phase != AttachmentJobPhase.cancelled) {
      return;
    }
    // Exit can cancel an import while its identity decision is awaiting input.
    // Release that await; the import coordinator still owns handle shutdown.
    setState(() {
      _cancelRequested = true;
      _conflict = null;
    });
    final decision = _decision;
    if (decision != null && !decision.isCompleted) {
      decision.complete(NoteImportDecision.ignore);
    }
  }

  Future<void> _run() async {
    if (!mounted) return;
    OperationResult<NoteImportResult> result;
    try {
      result = await widget.startImport(_resolveConflict);
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Import could not finish. Check the note and recovery status before retrying.',
      );
    }
    if (mounted) {
      setState(() {
        _result = result;
        _conflict = null;
      });
    }
  }

  Future<NoteImportDecision> _resolveConflict(
    NoteImportConflict conflict,
  ) async {
    if (!mounted || _cancelRequested) return NoteImportDecision.ignore;
    final decision = Completer<NoteImportDecision>();
    _decision = decision;
    setState(() => _conflict = conflict);
    final choice = await decision.future;
    _decision = null;
    return choice;
  }

  void _choose(NoteImportDecision choice) {
    final decision = _decision;
    if (decision == null || decision.isCompleted) return;
    setState(() => _conflict = null);
    decision.complete(choice);
  }

  Future<void> _signalCancellation() async {
    final job = _job?.progress.value;
    if (job == null || !job.cancellable || !_signalled.add(job.id)) return;
    try {
      await widget.cancelJob(job.id);
    } catch (_) {
      // Do not dismiss while worker ownership or publication is unresolved.
      _signalled.remove(job.id);
    }
  }

  void _cancel() {
    if (_result != null ||
        _job?.progress.value.phase == AttachmentJobPhase.finalizing) {
      return;
    }
    setState(() => _cancelRequested = true);
    unawaited(_signalCancellation());
  }

  @override
  void dispose() {
    widget.jobs.removeListener(_jobsChanged);
    _job?.progress.removeListener(_jobProgressChanged);
    final decision = _decision;
    if (decision != null && !decision.isCompleted) {
      decision.complete(NoteImportDecision.ignore);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _result != null,
    child: _conflict != null
        ? NoteReplacementDialog(
            conflict: _conflict!,
            fileName: widget.fileName,
            onDecision: _choose,
          )
        : _job != null && _result == null
        ? ValueListenableBuilder<AttachmentJobSnapshot>(
            valueListenable: _job!.progress,
            builder: (context, state, _) => _body(context, state),
          )
        : _body(context, null),
  );

  Widget _body(BuildContext context, AttachmentJobSnapshot? state) {
    final theme = Theme.of(context);
    final result = _result;
    final finishing = state?.phase == AttachmentJobPhase.finalizing;
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
    final detail = result == null
        ? _cancelRequested
              ? 'Cancelling import…'
              : finishing
              ? 'Finishing import…'
              : state?.phase == AttachmentJobPhase.verifying
              ? 'Checking the note and its attachments…'
              : 'Preparing the note package…'
        : result.isSuccess
        ? switch (result.value!.disposition) {
            NoteImportDisposition.created =>
              'The note is ready in your library.',
            NoteImportDisposition.duplicated =>
              'A separate note was created with a new ID. The existing note is unchanged.',
            NoteImportDisposition.replaced =>
              'The existing note was replaced. A verified recovery copy was retained.',
            NoteImportDisposition.ignored => 'The existing note is unchanged.',
          }
        : result.message ?? 'Import did not complete.';
    final total = state?.total;
    final bytes = state?.bytes ?? 0;
    final fraction =
        !finishing && !_cancelRequested && total != null && total > 0
        ? (bytes / total).clamp(0.0, 1.0)
        : null;
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
                    result == null
                        ? Icons.file_download_outlined
                        : result.isSuccess
                        ? Icons.check_circle_outline
                        : cancelled
                        ? Icons.cancel_outlined
                        : Icons.error_outline,
                    color: result != null && !result.isSuccess && !cancelled
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppTooltip(
                message: widget.fileName,
                child: Text(widget.fileName, softWrap: true),
              ),
              const SizedBox(height: 24),
              Text(detail),
              if (result == null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 8),
                Text(
                  finishing
                      ? 'Publication must finish before closing.'
                      : 'Preparing · Verifying · Finalizing',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: result != null
                    ? FilledButton(
                        autofocus: true,
                        onPressed: () => Navigator.pop(context, result),
                        child: const Text('Done'),
                      )
                    : TextButton(
                        onPressed: finishing || _cancelRequested
                            ? null
                            : _cancel,
                        child: Text(
                          finishing
                              ? 'Finishing…'
                              : _cancelRequested
                              ? 'Cancelling…'
                              : 'Cancel',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
