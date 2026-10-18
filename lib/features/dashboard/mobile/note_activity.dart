import 'package:flutter/foundation.dart';
import '../models/attachment_job.dart';

/// Opaque storage identities, compared as metadata; never resolved as paths.
@immutable
class NoteJobOwner {
  const NoteJobOwner({required this.library, required this.note});
  final String library;
  final String note;

  static NoteJobOwner? fromRecovery(Map<String, Object?>? metadata) {
    final library = metadata?['library'];
    final note = metadata?['target'];
    return library is String &&
            library.isNotEmpty &&
            note is String &&
            note.isNotEmpty
        ? NoteJobOwner(library: library, note: note)
        : null;
  }
}

@immutable
class NoteActivity {
  const NoteActivity(this.activeJobs);
  final int activeJobs;
  @override
  bool operator ==(Object other) =>
      other is NoteActivity && other.activeJobs == activeJobs;
  @override
  int get hashCode => activeJobs.hashCode;
}

/// Library-scoped, metadata-only presentation projection. No platform channel,
/// filesystem, timers, decryption or dependency on a particular list/filter.
class MobileNoteActivityController
    extends ValueNotifier<Map<String, NoteActivity>> {
  MobileNoteActivityController({
    required this.jobs,
    required this.library,
    required this.ownerOf,
  }) : super(const {}) {
    jobs.addListener(_refresh);
    _refresh();
  }
  final ValueListenable<List<AttachmentJobState>> jobs;
  final String library;
  final NoteJobOwner? Function(String jobId) ownerOf;
  final _observed = <AttachmentJobState>{};
  static const _operations = {
    AttachmentJobOperation.add,
    AttachmentJobOperation.open,
    AttachmentJobOperation.protection,
    AttachmentJobOperation.export,
  };

  void _refresh() {
    final current = jobs.value.toSet();
    for (final state in _observed.difference(current)) {
      state.phase.removeListener(_refresh);
    }
    for (final state in current.difference(_observed)) {
      state.phase.addListener(_refresh);
    }
    _observed
      ..clear()
      ..addAll(current);
    final counts = <String, int>{};
    for (final state in current) {
      final job = state.progress.value;
      if (!job.active || !_operations.contains(job.operation)) {
        continue;
      }
      final owner = ownerOf(job.id);
      if (owner == null || owner.library != library) {
        continue;
      }
      counts.update(owner.note, (count) => count + 1, ifAbsent: () => 1);
    }
    final next = {
      for (final entry in counts.entries) entry.key: NoteActivity(entry.value),
    };
    if (!mapEquals(value, next)) value = Map.unmodifiable(next);
  }

  @override
  void dispose() {
    jobs.removeListener(_refresh);
    for (final state in _observed) {
      state.phase.removeListener(_refresh);
    }
    _observed.clear();
    super.dispose();
  }
}
