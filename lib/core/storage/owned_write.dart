import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../platform/library_documents.dart';
import '../platform/mobile_library_documents.dart';

int _diagnosticType(FileSystemEntityType? type) {
  if (type == null) return -1;
  if (type == FileSystemEntityType.notFound) return 0;
  if (type == FileSystemEntityType.file) return 1;
  if (type == FileSystemEntityType.directory) return 2;
  if (type == FileSystemEntityType.link) return 3;
  return 9;
}

/// An intent to create a NEW output, never permission to overwrite an input.
/// Writers still create exclusively. Instances cannot be reconstructed from
/// document metadata, recovery JSON or a picked-source descriptor.
class OwnedWriteTarget {
  OwnedWriteTarget._(this.path, this.root, this.lease, [this.sink]);
  factory OwnedWriteTarget.forSink(LibraryOutputSinkLease sink) =>
      OwnedWriteTarget._(sink.path, '', sink.lease, sink);
  factory OwnedWriteTarget.forPath(String path) {
    if (!p.isAbsolute(path)) throw ArgumentError('Absolute output required.');
    final normalized = p.normalize(path);
    return OwnedWriteTarget._(
      normalized,
      p.dirname(normalized),
      const Uuid().v4(),
    );
  }
  final String path;
  final String root;
  final String lease;
  final LibraryOutputSinkLease? sink;
  bool _validated = false;
  bool _completed = false;
  Future<void> validate(
    String destination, {
    int macDiagnosticStage = 0,
  }) async {
    if (_validated || _completed)
      throw StateError('Output lease already used.');
    if (sink != null) {
      final doc = await MobileLibraryDocuments(
        kind: sink!.library.kind,
      ).checkOutputSink(sink!);
      if (destination != path ||
          doc.token != sink!.document.token ||
          doc.length != 0) {
        throw const FormatException('Provider output lease changed.');
      }
      _validated = true;
      return;
    }
    if (Platform.isMacOS) {
      Never reject(int predicate, [FileSystemEntityType? type]) {
        print(
          'FN_OWNED_WRITE_GUARD '
          'stage=$macDiagnosticStage '
          'predicate=$predicate '
          'type=${_diagnosticType(type)}',
        );
        throw const FormatException(
          'Output has no exclusive owned write target.',
        );
      }

      if (!p.equals(path, p.normalize(destination))) {
        reject(1);
      }
      final outputType = await FileSystemEntity.type(path, followLinks: false);
      if (outputType != FileSystemEntityType.notFound) {
        reject(2, outputType);
      }
      final rootType = await FileSystemEntity.type(root, followLinks: false);
      if (rootType != FileSystemEntityType.directory) {
        reject(3, rootType);
      }
      if (!p.equals(await Directory(root).resolveSymbolicLinks(), root)) {
        reject(4);
      }
      _validated = true;
      return;
    }
    if (!p.equals(path, p.normalize(destination)) ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await FileSystemEntity.type(root, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.equals(await Directory(root).resolveSymbolicLinks(), root)) {
      throw const FormatException(
        'Output has no exclusive owned write target.',
      );
    }
    _validated = true;
  }
}

/// Produced after a writer closes its exclusively-created candidate. Never
/// persist/reconstruct this capability: recovery uses the existing journal.
class OwnedWriteReceipt {
  OwnedWriteReceipt._(
    this.target,
    this.length,
    this.sha256Hex,
    this.modifiedMicros,
    this.changedMicros,
    this.verifyReadback,
    this.payloadReadBytes,
    this.readbackBytes,
    this.intermediateWriteBytes,
  );
  final OwnedWriteTarget target;
  String get path => target.path;
  final int length;
  final String sha256Hex;
  final int modifiedMicros;
  final int changedMicros;
  final bool verifyReadback;
  final int payloadReadBytes;
  final int readbackBytes;
  final int intermediateWriteBytes;
  static Future<OwnedWriteReceipt> closed({
    required OwnedWriteTarget target,
    required int length,
    required String sha256Hex,
    required bool verifyReadback,
    required int payloadReadBytes,
    int readbackBytes = 0,
    int intermediateWriteBytes = 0,
  }) async {
    if (!target._validated || target._completed) {
      throw const FormatException(
        'Output was not created under an owned lease.',
      );
    }
    final stat = await File(target.path).stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != length ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex) ||
        target.sink == null &&
            await FileSystemEntity.type(target.path, followLinks: false) !=
                FileSystemEntityType.file) {
      throw const FormatException(
        'Owned output changed before acknowledgement.',
      );
    }
    target._completed = true;
    return OwnedWriteReceipt._(
      target,
      length,
      sha256Hex,
      stat.modified.microsecondsSinceEpoch,
      stat.changed.microsecondsSinceEpoch,
      verifyReadback,
      payloadReadBytes,
      readbackBytes,
      intermediateWriteBytes,
    );
  }

  Future<bool> isCurrent([String? location]) async {
    if (target.sink != null) {
      if (location != null && location != path) return false;
      try {
        final sink = target.sink!;
        final doc = await MobileLibraryDocuments(
          kind: sink.library.kind,
        ).checkOutputSink(sink);
        if (doc.token != sink.document.token || doc.length != length)
          return false;
      } catch (_) {
        return false;
      }
    }
    final file = location ?? path;
    final stat = await File(file).stat();
    return (target.sink != null ||
            await FileSystemEntity.type(file, followLinks: false) ==
                FileSystemEntityType.file) &&
        stat.size == length &&
        stat.modified.microsecondsSinceEpoch == modifiedMicros &&
        (location != null ||
            stat.changed.microsecondsSinceEpoch == changedMicros);
  }
}
