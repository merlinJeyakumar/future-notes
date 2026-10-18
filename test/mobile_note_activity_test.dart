import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/note_activity.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';

void main() {
  test(
    'export activity follows exact library/note owner and terminal phase',
    () {
      AttachmentJobSnapshot snapshot(String id, AttachmentJobPhase phase) =>
          AttachmentJobSnapshot(
            id: id,
            owner: 1,
            fileName: 'Export package',
            phase: phase,
            operation: AttachmentJobOperation.export,
          );
      final current = AttachmentJobState(
        snapshot('current', AttachmentJobPhase.queued),
      );
      final foreign = AttachmentJobState(
        snapshot('foreign', AttachmentJobPhase.queued),
      );
      final unknown = AttachmentJobState(
        snapshot('unknown', AttachmentJobPhase.queued),
      );
      final jobs = ValueNotifier([current, foreign, unknown]);
      final projection = MobileNoteActivityController(
        jobs: jobs,
        library: 'library-a',
        ownerOf: (id) => id == 'unknown'
            ? null
            : NoteJobOwner(
                library: id == 'foreign' ? 'library-b' : 'library-a',
                note: 'note-a',
              ),
      );
      addTearDown(() {
        projection.dispose();
        jobs.dispose();
        current.dispose();
        foreign.dispose();
        unknown.dispose();
      });
      expect(projection.value, {'note-a': const NoteActivity(1)});
      var notifications = 0;
      projection.addListener(() => notifications++);
      current.update(snapshot('current', AttachmentJobPhase.decrypting));
      expect(notifications, 0);
      for (final phase in [
        AttachmentJobPhase.completed,
        AttachmentJobPhase.cancelled,
        AttachmentJobPhase.failed,
      ]) {
        current.update(snapshot('current', phase));
        expect(projection.value, isEmpty);
        current.update(snapshot('current', AttachmentJobPhase.queued));
        expect(projection.value, {'note-a': const NoteActivity(1)});
      }
      jobs.value = [foreign, unknown];
      expect(projection.value, isEmpty);
    },
  );
}
