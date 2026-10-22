import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'native_storage_primitives.dart';

/// Immutable, content-free journal intent. Version 1 records are canonical JSON.
/// Strict parsing fails closed; unsupported/damaged records require intervention.
class CommitRecord {
  CommitRecord({
    required this.transactionId,
    required this.target,
    required this.expected,
    required this.staged,
    this.windowsObjectPaths = false,
    this.caseSensitiveObjectPaths,
  }) {
    _validateIdentity(transactionId);
    _validateTarget(target);
    _validateRevision(expected);
    _validateRevision(staged);
    if (!staged.exists)
      throw const FormatException('Staged revision is required.');
  }

  static const maxRecordBytes = 64 * 1024;
  final String transactionId;
  final String target;
  final StorageRevision expected;
  final StorageRevision staged;

  /// Read Windows-authored journal identities on a case-sensitive mobile host.
  /// The target name and the encoded record remain byte-for-byte unchanged.
  final bool windowsObjectPaths;

  /// Explicit decode mode for strict portable compatibility fixtures. Null
  /// preserves the established host behavior for every existing caller.
  final bool? caseSensitiveObjectPaths;

  static String objectIdentity(String target) => sha256
      .convert(utf8.encode(p.separator == '\\' ? target.toLowerCase() : target))
      .toString();
  static String windowsObjectIdentity(String target) =>
      sha256.convert(utf8.encode(target.toLowerCase())).toString();
  String get objectId => caseSensitiveObjectPaths == true
      ? sha256.convert(utf8.encode(target)).toString()
      : windowsObjectPaths
      ? sha256.convert(utf8.encode(target.toLowerCase())).toString()
      : objectIdentity(target);
  String get stagePath => '.future-notes-storage/staging/$transactionId.staged';
  String get previousPath =>
      '.future-notes-storage/recovery/$objectId/$transactionId.previous';
  String get baselinePath =>
      '.future-notes-storage/recovery/$objectId/baseline';
  String get recordPath =>
      '.future-notes-storage/transactions/$transactionId.json';
  String get receiptPath =>
      '.future-notes-storage/transactions/$transactionId.receipt';
  String get recordHash => sha256.convert(utf8.encode(encode())).toString();

  String encode() => jsonEncode({
    'version': 1,
    'transactionId': transactionId,
    'target': target,
    'stage': stagePath,
    'previous': previousPath,
    'baseline': baselinePath,
    'expected': _revisionJson(expected),
    'staged': _revisionJson(staged),
  });

  static CommitRecord decode(
    String source, {
    bool windowsObjectPaths = false,
    bool? caseSensitiveObjectPaths,
  }) {
    try {
      final map = _boundedJson(source);
      if (map['version'] != 1 ||
          map['transactionId'] is! String ||
          map['target'] is! String) {
        throw const FormatException('Unsupported transaction record.');
      }
      final record = CommitRecord(
        transactionId: map['transactionId'] as String,
        target: map['target'] as String,
        expected: _readRevision(map['expected']),
        staged: _readRevision(map['staged']),
        windowsObjectPaths: windowsObjectPaths,
        caseSensitiveObjectPaths: caseSensitiveObjectPaths,
      );
      // Check derived paths and exact canonical shape, including duplicate keys,
      // unknown fields and unsupported versions. Never trust recorded paths.
      if (record.encode() != source) {
        throw const FormatException('Noncanonical transaction record.');
      }
      return record;
    } catch (_) {
      throw const FormatException('Invalid or unsupported transaction record.');
    }
  }

  /// Accept either exact canonical desktop authorship, retaining its original
  /// derived paths and receipt hash. Never rewrite the target or stored JSON.
  static CommitRecord decodeDesktopCompatible(
    String source, {
    bool? caseSensitiveObjectPaths,
  }) {
    if (!(caseSensitiveObjectPaths ?? (Platform.isMacOS || Platform.isLinux))) {
      return decode(source);
    }
    try {
      return decode(source, caseSensitiveObjectPaths: true);
    } on FormatException {
      return decode(source, windowsObjectPaths: true);
    }
  }

  /// Resolve only after the caller's root containment/link checks and lease.
  String resolve(String root, String relativePath) {
    if (!p.isAbsolute(root) ||
        p.split(root).contains('..') ||
        ![
          target,
          stagePath,
          previousPath,
          baselinePath,
          recordPath,
          receiptPath,
        ].contains(relativePath)) {
      throw const FormatException('Invalid transaction location.');
    }
    final location = p.normalize(p.join(root, relativePath));
    if (!p.isWithin(p.normalize(root), location)) {
      throw const FormatException('Transaction location escapes its root.');
    }
    return location;
  }
}

enum CommitDisposition { completed, restored }

/// A receipt is accepted only for its exact immutable intent and revision.
class CommitReceipt {
  CommitReceipt(this.record, this.disposition, this.published) {
    _validateRevision(published);
    final required = disposition == CommitDisposition.completed
        ? record.staged
        : record.expected;
    if (published.length != required.length ||
        published.sha256Hex != required.sha256Hex) {
      throw const FormatException(
        'Receipt revision does not match transaction.',
      );
    }
  }

  final CommitRecord record;
  final CommitDisposition disposition;
  final StorageRevision published;

  String encode() => jsonEncode({
    'version': 1,
    'transactionId': record.transactionId,
    'recordHash': record.recordHash,
    'disposition': disposition.name,
    'published': _revisionJson(published),
  });

  static CommitReceipt decode(String source, CommitRecord record) {
    try {
      final map = _boundedJson(source);
      if (map['version'] != 1 ||
          map['transactionId'] != record.transactionId ||
          map['recordHash'] != record.recordHash) {
        throw const FormatException('Receipt does not match transaction.');
      }
      final disposition = CommitDisposition.values.firstWhere(
        (v) => v.name == map['disposition'],
      );
      final receipt = CommitReceipt(
        record,
        disposition,
        _readRevision(map['published']),
      );
      if (receipt.encode() != source) {
        throw const FormatException('Noncanonical receipt.');
      }
      return receipt;
    } catch (_) {
      throw const FormatException(
        'Invalid or unsupported transaction receipt.',
      );
    }
  }
}

Map<String, dynamic> _boundedJson(String source) {
  // Bound before parsing/allocation. The later file reader must also bound bytes
  // before constructing source; this parser cannot make an unbounded read safe.
  if (source.length > CommitRecord.maxRecordBytes ||
      utf8.encode(source).length > CommitRecord.maxRecordBytes) {
    throw const FormatException('Transaction metadata exceeds its bound.');
  }
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid transaction metadata.');
  }
  return decoded;
}

void _validateIdentity(String id) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
    throw const FormatException('Invalid transaction identity.');
  }
}

void _validateTarget(String target) {
  if (target.isEmpty ||
      utf8.encode(target).length > 4096 ||
      target.contains('\\') ||
      target.contains(':') ||
      target.contains('\u0000') ||
      target.startsWith('/') ||
      target
          .split('/')
          .any(
            (part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part.toLowerCase().startsWith('.future-notes-') ||
                RegExp(r'[<>|?*\x00-\x1f]').hasMatch(part) ||
                part.endsWith('.') ||
                part.endsWith(' ') ||
                RegExp(
                  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
                  caseSensitive: false,
                ).hasMatch(part),
          ) ||
      p.posix.normalize(target) != target ||
      p.windows.normalize(target).replaceAll('\\', '/') != target) {
    throw const FormatException('Invalid transaction target.');
  }
}

void _validateRevision(StorageRevision revision) {
  if (!revision.exists) {
    if (revision.length != null || revision.modifiedMicros != null) {
      throw const FormatException('Invalid missing revision.');
    }
    return;
  }
  if (revision.length == null ||
      revision.length! < 0 ||
      revision.modifiedMicros == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision.sha256Hex!)) {
    throw const FormatException('Invalid stored revision.');
  }
}

Map<String, dynamic> _revisionJson(StorageRevision revision) => {
  'exists': revision.exists,
  'length': revision.length,
  'sha256': revision.sha256Hex,
  'modifiedMicros': revision.modifiedMicros,
};

StorageRevision _readRevision(Object? value) {
  if (value is! Map<String, dynamic> || value['exists'] is! bool) {
    throw const FormatException('Invalid transaction revision.');
  }
  if (value['exists'] == false) {
    if (value['length'] != null ||
        value['sha256'] != null ||
        value['modifiedMicros'] != null) {
      throw const FormatException('Invalid missing transaction revision.');
    }
    return const StorageRevision.missing();
  }
  if (value['length'] is! int ||
      value['sha256'] is! String ||
      value['modifiedMicros'] is! int) {
    throw const FormatException('Invalid transaction revision fields.');
  }
  return StorageRevision.present(
    value['length'] as int,
    value['sha256'] as String,
    value['modifiedMicros'] as int,
  );
}
