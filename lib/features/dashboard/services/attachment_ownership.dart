import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import '../../../core/operations/operation_result.dart';
import '../../../core/storage/commit_record.dart';
import '../../../core/storage/note_reference.dart';
import '../../../core/storage/storage_environment.dart';
import 'encryption_service.dart';
import 'note_codec.dart';

/// Older loose-note imports can share a persistent ID with a folder or another
/// loose note. Refuse destructive ownership guesses; new imports use fresh IDs.
Future<OperationResult<void>> verifyAttachmentOwnership(
  NoteReference reference,
  StorageEnvironment environment,
) => Isolate.run(() async {
  try {
    final location = reference.attachmentLocation;
    final folder = p.dirname(location);
    final folderName = p.basename(folder);
    if (!folderName.startsWith('note_'))
      throw const FormatException('Unknown attachment owner.');
    await environment.verifyLocation(location);
    var hasManagedPayloads = await Directory(location).exists();
    if (!hasManagedPayloads) {
      final directory = Directory(
        reference.binding.child('.future-notes-storage/transactions'),
      );
      if (await directory.exists()) {
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is! File || !entry.path.endsWith('.json')) continue;
          await environment.verifyLocation(entry.path);
          final input = await entry.open();
          String text;
          try {
            final bytes = await input.read(CommitRecord.maxRecordBytes + 1);
            if (bytes.length > CommitRecord.maxRecordBytes)
              throw const FormatException('Invalid ownership journal.');
            text = utf8.decode(bytes);
          } finally {
            await input.close();
          }
          final record = CommitRecord.decode(text);
          final relative = p.posix.joinAll(
            p.split(p.relative(location, from: reference.binding.root)),
          );
          if (p.equals(p.posix.dirname(record.target), relative)) {
            hasManagedPayloads = true;
            break;
          }
        }
      }
    }
    if (!hasManagedPayloads) return const OperationResult<void>.success();
    final id = folderName.substring(5);
    final folderNote = p.join(folder, 'note_content_$id.enc');
    if (!p.equals(folderNote, reference.contentPath) &&
        await File(folderNote).exists()) {
      return const OperationResult<void>.failure(
        OperationOutcome.conflict,
        'Attachments are shared with another existing note. Nothing was deleted.',
      );
    }
    var count = 0;
    await for (final entry in Directory(
      reference.binding.root,
    ).list(followLinks: false)) {
      if (entry is Directory || p.equals(entry.path, reference.contentPath))
        continue;
      final name = p.basename(entry.path);
      if (!name.startsWith('note_') &&
          p.extension(name).toLowerCase() != '.enc')
        continue;
      if (++count > 10000 || entry is! File)
        throw const FormatException('Ownership inventory unavailable.');
      await environment.verifyLocation(entry.path);
      const limit = 64 * 1024 * 1024;
      final before = await entry.stat();
      if (before.size > limit)
        throw const FormatException('Ownership metadata exceeds bound.');
      final input = await entry.open();
      String content;
      try {
        final bytes = await input.read(limit + 1);
        if (bytes.length != before.size)
          throw const FormatException('Ownership metadata changed.');
        content = utf8.decode(bytes);
      } finally {
        await input.close();
      }
      final decoded = NoteCodec.decodeSync(
        content,
        decryptApp: EncryptionService.decryptAppResultSync,
      );
      final after = await entry.stat();
      if (before.size != after.size || before.modified != after.modified)
        throw const FormatException('Ownership metadata changed.');
      if (p.equals(
        reference.binding.child('note_${decoded.note.id}/attachments'),
        location,
      )) {
        return const OperationResult<void>.failure(
          OperationOutcome.conflict,
          'Attachments are shared with another existing note. Nothing was deleted.',
        );
      }
    }
    return const OperationResult<void>.success();
  } catch (_) {
    return const OperationResult<void>.failure(
      OperationOutcome.conflict,
      'Attachment ownership could not be verified. Nothing was deleted.',
    );
  }
});
