import 'package:flutter/foundation.dart';

enum AttachmentJobOperation { add, open, protection, export, import }

enum AttachmentJobPhase {
  queued,
  preparing,
  decrypting,
  encrypting,
  verifying,
  finalizing,
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
    this.batch = false,
    this.originalAttachmentId,
    this.operation = AttachmentJobOperation.add,
  });
  final String id;
  final int owner;
  final String fileName;
  final AttachmentJobPhase phase;
  final int bytes;
  final int? total;
  final String? error;
  final bool batch;
  final String? originalAttachmentId;
  final AttachmentJobOperation operation;
  bool get active => ![
    AttachmentJobPhase.completed,
    AttachmentJobPhase.cancelled,
    AttachmentJobPhase.failed,
  ].contains(phase);
  bool get cancellable => active && phase != AttachmentJobPhase.finalizing;
}

class AttachmentJobState {
  AttachmentJobState(AttachmentJobSnapshot initial)
    : progress = ValueNotifier(initial);
  final ValueNotifier<AttachmentJobSnapshot> progress;
  final _clock = Stopwatch()..start();
  int _last = -200;
  void update(AttachmentJobSnapshot snapshot) {
    if (snapshot.phase == progress.value.phase &&
        snapshot.active &&
        _clock.elapsedMilliseconds - _last < 200) {
      return;
    }
    _last = _clock.elapsedMilliseconds;
    progress.value = snapshot;
  }

  void dispose() => progress.dispose();
}
