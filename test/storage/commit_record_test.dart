import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/commit_record.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';

void main() {
  const identity = '0123456789abcdef0123456789abcdef';
  const old = StorageRevision.present(
    3,
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    1700000000000000,
  );
  const next = StorageRevision.present(
    0,
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    1700000000000001,
  );
  CommitRecord record({
    StorageRevision expected = old,
    String target = 'note_synthetic/note_content_synthetic.enc',
  }) => CommitRecord(
    transactionId: identity,
    target: target,
    expected: expected,
    staged: next,
  );

  test(
    'canonical intent retains expected/staged revisions and derived paths',
    () {
      final intent = record();
      final decoded = CommitRecord.decode(intent.encode());
      expect(decoded.expected.matches(old), isTrue);
      expect(decoded.staged.matches(next), isTrue);
      expect(decoded.encode(), intent.encode());
      expect(
        decoded.stagePath,
        '.future-notes-storage/staging/$identity.staged',
      );
      expect(decoded.objectId, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(decoded.recordHash, intent.recordHash);
    },
  );

  test(
    'new-target intent preserves absence separately from staged empty content',
    () {
      final intent = CommitRecord.decode(
        record(expected: const StorageRevision.missing()).encode(),
      );
      expect(intent.expected.exists, isFalse);
      expect(intent.staged.exists, isTrue);
      expect(intent.staged.length, 0);
    },
  );

  test(
    'target/path aliases, device names and internal metadata targets are rejected',
    () {
      for (final target in [
        '',
        '/outside.enc',
        '../outside.enc',
        'a/../b',
        'a//b',
        'a\\b',
        'C:/outside.enc',
        'a:stream',
        'a/./b',
        'a\u0000b',
        'CON',
        'LPT1.enc',
        'a?.enc',
        'a. ',
        'a.',
        '.future-notes-storage/other',
        '.FUTURE-NOTES-storage/other',
      ]) {
        expect(
          () => record(target: target),
          throwsFormatException,
          reason: target,
        );
      }
    },
  );

  test(
    'malformed IDs, revisions and oversized target metadata fail closed',
    () {
      for (final id in ['', 'UPPERCASE', '../elsewhere', '0' * 33]) {
        expect(
          () => CommitRecord(
            transactionId: id,
            target: 'a.enc',
            expected: old,
            staged: next,
          ),
          throwsFormatException,
        );
      }
      for (final revision in [
        const StorageRevision.missing(),
        const StorageRevision.present(-1, 'not-a-hash', 0),
        const StorageRevision.present(0, 'not-a-hash', 0),
      ]) {
        expect(
          () => CommitRecord(
            transactionId: identity,
            target: 'a.enc',
            expected: old,
            staged: revision,
          ),
          throwsFormatException,
        );
      }
      expect(() => record(target: 'a' * 4097), throwsFormatException);
    },
  );

  test(
    'tampered paths/version/unknown fields never become a recovery intent',
    () {
      final original = jsonDecode(record().encode()) as Map<String, dynamic>;
      for (final changed in [
        {...original, 'stage': '../external.enc'},
        {...original, 'previous': 'unrelated.enc'},
        {...original, 'baseline': 'unrelated.enc'},
        {...original, 'version': 2},
        {...original, 'extra': true},
        {
          ...original,
          'expected': {'exists': false, 'length': 3},
        },
      ]) {
        expect(
          () => CommitRecord.decode(jsonEncode(changed)),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'duplicate keys, reordered/noncanonical and oversized JSON are rejected',
    () {
      final source = record().encode();
      expect(
        () => CommitRecord.decode(source.replaceFirst('{', '{"version":1,')),
        throwsFormatException,
      );
      expect(() => CommitRecord.decode(' $source'), throwsFormatException);
      expect(
        () =>
            CommitRecord.decode('{' + ' ' * CommitRecord.maxRecordBytes + '}'),
        throwsFormatException,
      );
      expect(() => CommitRecord.decode('[]'), throwsFormatException);
    },
  );

  test('only reviewed relative objects resolve under an absolute root', () {
    final intent = record();
    final root = p.current;
    for (final relative in [
      intent.target,
      intent.stagePath,
      intent.previousPath,
      intent.baselinePath,
      intent.recordPath,
      intent.receiptPath,
    ]) {
      expect(p.isWithin(root, intent.resolve(root, relative)), isTrue);
    }
    expect(() => intent.resolve(root, '../outside'), throwsFormatException);
    expect(
      () => intent.resolve('relative', intent.target),
      throwsFormatException,
    );
  });

  test('completion receipts bind exact intent and content revision', () {
    final intent = record();
    final receipt = CommitReceipt(intent, CommitDisposition.completed, next);
    final decoded = CommitReceipt.decode(receipt.encode(), intent);
    expect(decoded.disposition, CommitDisposition.completed);
    expect(decoded.published.matches(next), isTrue);
    expect(
      () => CommitReceipt(intent, CommitDisposition.completed, old),
      throwsFormatException,
    );
    expect(
      () => CommitReceipt.decode(
        receipt.encode(),
        record(target: 'different.enc'),
      ),
      throwsFormatException,
    );
  });

  test('restoration receipts require prior content or prior absence', () {
    final intent = record();
    final restored = CommitReceipt.decode(
      CommitReceipt(intent, CommitDisposition.restored, old).encode(),
      intent,
    );
    expect(restored.published.matches(old), isTrue);
    final newTarget = record(expected: const StorageRevision.missing());
    final absent = CommitReceipt.decode(
      CommitReceipt(
        newTarget,
        CommitDisposition.restored,
        const StorageRevision.missing(),
      ).encode(),
      newTarget,
    );
    expect(absent.published.exists, isFalse);
    expect(
      () => CommitReceipt(intent, CommitDisposition.restored, next),
      throwsFormatException,
    );
  });

  test('damaged or unbound receipt cannot acknowledge a commit', () {
    final intent = record();
    final original =
        jsonDecode(
              CommitReceipt(intent, CommitDisposition.completed, next).encode(),
            )
            as Map<String, dynamic>;
    for (final changed in [
      {...original, 'recordHash': '0' * 64},
      {...original, 'transactionId': '0' * 32},
      {...original, 'disposition': 'unknown'},
      {...original, 'version': 2},
      {...original, 'extra': true},
      {
        ...original,
        'published': {'exists': true, 'length': 1.5},
      },
    ]) {
      expect(
        () => CommitReceipt.decode(jsonEncode(changed), intent),
        throwsFormatException,
      );
    }
  });
}
