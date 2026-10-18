import 'package:flutter/foundation.dart';
import '../../../core/storage/file_operation_progress.dart';

enum AttachmentJobOperation { add, open, protection, export, import }

enum AttachmentJobPhase {
  queued,
  preparing,
  decrypting,
  encrypting,
  verifying,
  finalizing,
  cancelling,
  completed,
  cancelled,
  failed,
}

class AttachmentJobSnapshot {
  const AttachmentJobSnapshot({
    required this.id,
    required this.owner,
    required this.fileName,
    required this.phase,
    this.bytes = 0,
    this.total,
    this.error,
    this.detail,
    this.batch = false,
    this.originalAttachmentId,
    this.attachmentIds = const [],
    this.operation = AttachmentJobOperation.add,
    this.fileProgress,
  });
  final String id;
  final int owner;
  final String fileName;
  final AttachmentJobPhase phase;
  final int bytes;
  final int? total;
  final String? error;
  final String? detail;
  final bool batch;
  final String? originalAttachmentId;

  /// Storage identities affected by a batch; never matched by filename.
  final List<String> attachmentIds;
  final AttachmentJobOperation operation;
  final FileOperationProgress? fileProgress;
  bool get active => ![
    AttachmentJobPhase.completed,
    AttachmentJobPhase.cancelled,
    AttachmentJobPhase.failed,
  ].contains(phase);
  bool get cancellable =>
      active &&
      phase != AttachmentJobPhase.finalizing &&
      phase != AttachmentJobPhase.cancelling;
}

class AttachmentJobState {
  AttachmentJobState(AttachmentJobSnapshot initial)
    : progress = ValueNotifier(initial),
      phase = ValueNotifier(initial.phase);
  final ValueNotifier<AttachmentJobSnapshot> progress;
  final ValueNotifier<AttachmentJobPhase> phase;
  final _clock = Stopwatch()..start();
  int _last = -200;
  bool _disposed = false;
  void update(AttachmentJobSnapshot snapshot) {
    if (_disposed) return;
    if (snapshot.phase == progress.value.phase &&
        snapshot.detail == progress.value.detail &&
        snapshot.originalAttachmentId == progress.value.originalAttachmentId &&
        snapshot.bytes != snapshot.total &&
        snapshot.active &&
        _clock.elapsedMilliseconds - _last < 200) {
      return;
    }
    _last = _clock.elapsedMilliseconds;
    progress.value = snapshot;
    phase.value = snapshot.phase;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    progress.dispose();
    phase.dispose();
  }
}
