import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import '../platform/macos_file_access.dart';
import 'owned_write.dart';

/// Per-job authority from NSSavePanel. The normal transform writes directly to
/// its owned replacement candidate; there is no extra transfer or payload scan.
class MacosExportTarget {
  MacosExportTarget._(this._grant);
  final MacosSaveGrant _grant;
  bool _publicationAttempted = false;
  bool get retainCandidate => _publicationAttempted;
  String get destination => _grant.path;
  String get candidate => _grant.candidate;

  static Future<MacosExportTarget?> choose(
    String suggestedName, {
    MacosFileAccess access = const MacosFileAccess(),
  }) async {
    final grant = await access.chooseSaveTarget(suggestedName: suggestedName);
    return grant == null ? null : MacosExportTarget._(grant);
  }

  Future<OperationResult<void>> publish(OwnedWriteReceipt receipt) async {
    if (_publicationAttempted) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'The save lease has already been used.',
      );
    }
    if (!p.equals(receipt.path, candidate) || !await receipt.isCurrent()) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'The export candidate changed; the destination was retained.',
      );
    }
    try {
      _publicationAttempted = true;
      await _grant.publish(
        length: receipt.length,
        modifiedMicros: receipt.modifiedMicros,
        changedMicros: receipt.changedMicros,
      );
      return const OperationResult.success();
    } catch (error) {
      // Fixed numeric reasons only: no exception messages or destination paths.
      final reason = error is PlatformException
          ? const {
                  'conflict': 1,
                  'access_denied': 2,
                  'access_unavailable': 3,
                  'invalid_grant': 4,
                  'recovery_required': 5,
                }[error.code] ??
                0
          : 0;
      print('FN_MAC_EXPORT_PUBLISH failure=$reason');
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'The export could not be acknowledged. Retained files require recovery.',
      );
    }
  }

  Future<void> close() => _grant.close();

  Future<String> nextCandidate() async {
    final prior = candidate;
    // The failed transform has joined before retry. Only its native-issued,
    // exclusively created output can be removed; picked inputs are never here.
    final type = await FileSystemEntity.type(prior, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await File(prior).delete();
    } else if (type != FileSystemEntityType.notFound) {
      throw const FormatException('The save candidate identity changed.');
    }
    return _grant.nextCandidate();
  }
}
