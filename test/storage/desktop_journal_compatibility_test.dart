import 'dart:convert';

import 'package:flutter_application_1/core/storage/commit_record.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CommitRecord record({required bool windows}) => CommitRecord(
    transactionId: '11111111111111111111111111111111',
    target: 'Mixed CASE – note.enc',
    expected: const StorageRevision.missing(),
    staged: StorageRevision.present(17, 'a' * 64, 123),
    windowsObjectPaths: windows,
    caseSensitiveObjectPaths: windows ? null : true,
  );

  for (final windows in [false, true]) {
    test(
      'strict desktop reader preserves ${windows ? 'Windows' : 'POSIX'} authorship and receipts',
      () {
        final authored = record(windows: windows);
        final encoded = authored.encode();
        final decoded = CommitRecord.decodeDesktopCompatible(
          encoded,
          caseSensitiveObjectPaths: true,
        );
        expect(decoded.encode(), encoded);
        expect(decoded.target, authored.target);
        expect(decoded.objectId, authored.objectId);
        expect(decoded.previousPath, authored.previousPath);
        expect(decoded.recordHash, authored.recordHash);
        final receipt = CommitReceipt(
          authored,
          CommitDisposition.completed,
          authored.staged,
        );
        expect(
          CommitReceipt.decode(receipt.encode(), decoded).encode(),
          receipt.encode(),
        );
      },
    );
  }

  test(
    'compatibility cannot admit arbitrary paths, unknown fields or altered receipts',
    () {
      final encoded = record(windows: true).encode();
      final fields = jsonDecode(encoded) as Map<String, dynamic>;
      for (final changed in [
        {
          ...fields,
          'previous': '.future-notes-storage/recovery/unrelated/previous',
        },
        {...fields, 'stage': '../outside'},
        {...fields, 'unknown': true},
        {...fields, 'version': 2},
      ]) {
        expect(
          () => CommitRecord.decodeDesktopCompatible(
            jsonEncode(changed),
            caseSensitiveObjectPaths: true,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => CommitRecord.decodeDesktopCompatible(
          '$encoded ',
          caseSensitiveObjectPaths: true,
        ),
        throwsFormatException,
      );
    },
  );
}
