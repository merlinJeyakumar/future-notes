import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../../../core/operations/operation_result.dart';
import '../../../core/theme/app_dialog.dart';
import '../../../core/platform/mobile_export.dart';
import '../../../core/platform/prepared_mobile_export.dart';
import 'package:path/path.dart' as p;
import '../models/attachment_job.dart';
import '../viewmodels/content_viewmodel.dart';
import '../widgets/attachment_presentation.dart';

/// Hide/Back dismiss presentation only; the existing coordinator owns the job.
Future<OperationResult<void>> showMobileExportProgress({
  required BuildContext context,
  required ContentViewModel model,
  String? noteTitle,
  Future<OperationResult<void>> Function()? start,
  AttachmentJobState? existingJob,
  VoidCallback? onHidden,
}) async {
  assert((start == null) != (existingJob == null));
  final before = model.attachmentJobsNotifier.value
      .map((s) => s.progress.value.id)
      .toSet();
  final navigator = Navigator.of(context, rootNavigator: true);
  final completion = ValueNotifier<OperationResult<void>?>(null);
  var presentationClosed = false;
  final owner = (
    model.draftSession.generation,
    model.currentContentPath,
    model.draftSession.credentialGeneration,
    model.isLocked,
  );
  final route = AppDialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MobileExportProgressDialog(
      model: model,
      noteTitle: noteTitle,
      excludedIds: before,
      existingJob: existingJob,
      completion: completion,
    ),
  );
  void invalidate() {
    if (owner !=
            (
              model.draftSession.generation,
              model.currentContentPath,
              model.draftSession.credentialGeneration,
              model.isLocked,
            ) &&
        route.isActive) {
      navigator.removeRoute(route);
    }
  }

  model.addListener(invalidate);
  final closed = navigator.push(route).whenComplete(() {
    presentationClosed = true;
    model.removeListener(invalidate);
    completion.dispose();
    onHidden?.call();
  });
  // Paint the route before storage preparation can start or await provider I/O.
  await WidgetsBinding.instance.endOfFrame;
  OperationResult<void> result;
  try {
    result = start != null
        ? await start()
        : await _settled(existingJob!, closed);
  } catch (_) {
    result = const OperationResult.failure(
      OperationOutcome.ioFailure,
      'Export could not be completed. The original note was retained.',
    );
  }
  // The job and export lock settle now. The result route has its own lifetime.
  if (!presentationClosed) completion.value = result;
  return result;
}

Future<OperationResult<void>> _settled(
  AttachmentJobState job,
  Future<void> hidden,
) async {
  final completion = Completer<void>();
  void changed() {
    if (!job.progress.value.active && !completion.isCompleted) {
      completion.complete();
    }
  }

  job.phase.addListener(changed);
  // A reopened viewer need not retain a listener after Hide. The original
  // operation remains owned by its initiating flow and the storage coordinator.
  unawaited(
    hidden.then((_) {
      if (!completion.isCompleted) completion.complete();
    }),
  );
  changed();
  try {
    await completion.future;
    final state = job.progress.value;
    if (state.active) {
      return const OperationResult.failure(OperationOutcome.cancelled, null);
    }
    return state.phase == AttachmentJobPhase.completed
        ? const OperationResult.success()
        : OperationResult.failure(
            state.phase == AttachmentJobPhase.cancelled
                ? OperationOutcome.cancelled
                : OperationOutcome.ioFailure,
            state.error,
          );
  } finally {
    job.phase.removeListener(changed);
  }
}

class MobileExportProgressDialog extends StatefulWidget {
  const MobileExportProgressDialog({
    super.key,
    required this.model,
    this.noteTitle,
    this.excludedIds = const {},
    this.existingJob,
    this.completion,
  });
  final ContentViewModel model;
  final String? noteTitle;
  final Set<String> excludedIds;
  final AttachmentJobState? existingJob;
  final ValueListenable<OperationResult<void>?>? completion;

  @override
  State<MobileExportProgressDialog> createState() =>
      _MobileExportProgressDialogState();
}

class _MobileExportProgressDialogState
    extends State<MobileExportProgressDialog> {
  ContentViewModel get model => widget.model;
  String? get noteTitle => widget.noteTitle;
  Set<String> get excludedIds => widget.excludedIds;
  AttachmentJobState? get existingJob => widget.existingJob;
  ValueListenable<OperationResult<void>?>? get completion => widget.completion;
  bool _acting = false, _saving = false;
  int _bytes = 0;
  int? _total;
  String? _message;

  Future<void> _handoff(PreparedMobileExport file, {required bool save}) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _saving = save;
      _bytes = 0;
      _total = null;
      _message = null;
    });
    try {
      if (!await file.isCurrent()) {
        throw StateError('Prepared export unavailable.');
      }
      final accepted = save
          ? await MobileExport.save(
              file.path,
              onProgress: (bytes, total) {
                if (mounted) {
                  setState(() {
                    _bytes = bytes;
                    _total = total;
                  });
                }
              },
            )
          : await MobileExport.sharePrepared(file.path);
      if (mounted) {
        setState(
          () => _message = save
              ? accepted
                    ? 'Saved to files.'
                    : 'Save cancelled.'
              : accepted
              ? 'Share sheet opened.'
              : 'Sharing cancelled.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not ${save ? 'save' : 'share'}. Your export is still available. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => completion == null
      ? _build(context, null)
      : ValueListenableBuilder<OperationResult<void>?>(
          valueListenable: completion!,
          builder: (context, result, _) => _build(context, result),
        );

  Widget _build(
    BuildContext context,
    OperationResult<void>? result,
  ) => ValueListenableBuilder<List<AttachmentJobState>>(
    valueListenable: model.attachmentJobsNotifier,
    builder: (context, states, _) {
      final matches = existingJob == null
          ? states
                .where(
                  (state) =>
                      state.progress.value.operation ==
                          AttachmentJobOperation.export &&
                      !excludedIds.contains(state.progress.value.id),
                )
                .toList()
          : [existingJob!];
      return ListenableBuilder(
        listenable: Listenable.merge(matches.map((s) => s.progress).toList()),
        builder: (context, _) {
          final job = matches.isEmpty ? null : matches.last.progress.value;
          final total = job?.total;
          final finished = result != null || job?.active == false;
          final success =
              result?.isSuccess ?? job?.phase == AttachmentJobPhase.completed;
          final cancelled =
              result?.outcome == OperationOutcome.cancelled ||
              job?.phase == AttachmentJobPhase.cancelled;
          final waiting =
              job == null ||
              job.phase == AttachmentJobPhase.cancelling ||
              (job.phase == AttachmentJobPhase.finalizing && total == null);
          final fraction = !waiting && total != null && total > 0
              ? (job.bytes / total).clamp(0.0, 1.0)
              : null;
          final prepared = job == null
              ? null
              : model.preparedExportForJob(job.id);
          if (finished && success && prepared != null) {
            return _readyDialog(
              context,
              prepared,
              reused: job?.detail == 'Using prepared export',
            );
          }
          return PopScope(
            canPop: !_acting,
            child: AlertDialog(
              key: const ValueKey('mobile-export-dialog'),
              title: Text(
                existingJob != null &&
                        (job?.originalAttachmentId != null ||
                            job?.attachmentIds.isNotEmpty == true)
                    ? 'Export attachments'
                    : 'Export note',
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (noteTitle?.isNotEmpty == true) ...[
                      Text(
                        noteTitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      finished
                          ? (success
                                ? 'Export complete'
                                : cancelled
                                ? 'Export cancelled'
                                : result?.message ??
                                      job?.error ??
                                      'Export failed.')
                          : job?.detail ??
                                (job == null
                                    ? 'Preparing export…'
                                    : job.phase == AttachmentJobPhase.preparing
                                    ? 'Preparing export…'
                                    : job.phase == AttachmentJobPhase.finalizing
                                    ? 'Finishing export…'
                                    : attachmentPhaseLabel(job.phase)),
                    ),
                    const SizedBox(height: 12),
                    if (!finished)
                      LinearProgressIndicator(value: fraction)
                    else
                      Icon(
                        success
                            ? Icons.check_circle_outline
                            : cancelled
                            ? Icons.cancel_outlined
                            : Icons.error_outline,
                      ),
                    if (!waiting && total != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${formatAttachmentBytes(job.bytes)} / ${formatAttachmentBytes(total)}'
                        '${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}',
                      ),
                    ],
                    if (!finished) ...[
                      const SizedBox(height: 16),
                      const Text('Export continues if you hide this window.'),
                    ],
                    if (_acting && _saving) ...[
                      const SizedBox(height: 12),
                      Text(
                        _total == null
                            ? 'Choose a save location…'
                            : 'Saving file',
                      ),
                      LinearProgressIndicator(
                        value: _total != null && _total! > 0
                            ? (_bytes / _total!).clamp(0.0, 1.0)
                            : null,
                      ),
                      if (_total != null)
                        Text(
                          '${formatAttachmentBytes(_bytes)} / ${formatAttachmentBytes(_total!)}${_total! > 0 ? ' · ${(_bytes * 100 / _total!).floor()}%' : ''}',
                        ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!),
                    ],
                  ],
                ),
              ),
              scrollable: true,
              actions: [
                TextButton(
                  onPressed: _acting ? null : () => Navigator.pop(context),
                  child: Text(finished ? 'Close' : 'Hide'),
                ),
                if (!finished && job?.cancellable == true)
                  TextButton(
                    onPressed: () => model.cancelAttachmentJob(job!.id),
                    child: const Text('Cancel export'),
                  ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _readyDialog(
    BuildContext context,
    PreparedMobileExport file, {
    required bool reused,
  }) {
    final theme = Theme.of(context);
    final stacked =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.padded,
      minimumSize: WidgetStateProperty.all(const Size(0, 48)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
    final share = OutlinedButton.icon(
      style: buttonStyle,
      onPressed: _acting ? null : () => _handoff(file, save: false),
      icon: const Icon(Icons.share_outlined, size: 20),
      label: const Text('Share'),
    );
    final close = TextButton(
      style: buttonStyle,
      onPressed: _acting ? null : () => Navigator.pop(context),
      child: const Text('Close'),
    );
    return SafeArea(
      child: PopScope(
        canPop: !_acting,
        child: AlertDialog(
          key: const ValueKey('mobile-export-dialog'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          title: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: theme.colorScheme.primary,
                size: 26,
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Export ready')),
            ],
          ),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: .45,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 26,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(file.path),
                                style: theme.textTheme.titleSmall,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${p.extension(file.path).substring(1).toUpperCase()} · ${formatAttachmentBytes(file.length)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_acting && _saving) ...[
                  const SizedBox(height: 16),
                  Text(
                    _total == null ? 'Choose a save location…' : 'Saving file',
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _total != null && _total! > 0
                        ? (_bytes / _total!).clamp(0.0, 1.0)
                        : null,
                  ),
                  if (_total != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${formatAttachmentBytes(_bytes)} / ${formatAttachmentBytes(_total!)}${_total! > 0 ? ' · ${(_bytes * 100 / _total!).floor()}%' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ] else if (_message != null || reused) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message ?? 'Using prepared export',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    style: buttonStyle,
                    onPressed: _acting
                        ? null
                        : () => _handoff(file, save: true),
                    icon: const Icon(Icons.save_alt, size: 20),
                    label: const Text('Save'),
                  ),
                  const SizedBox(height: 8),
                  if (stacked) ...[
                    share,
                    const SizedBox(height: 4),
                    close,
                  ] else
                    Row(
                      children: [
                        Expanded(child: share),
                        const SizedBox(width: 8),
                        Expanded(child: close),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
