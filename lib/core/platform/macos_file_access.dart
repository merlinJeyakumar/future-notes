import 'package:flutter/services.dart';

/// Sandbox authority is issued by native Open panels/bookmarks, never by a path.
/// Construct this adapter only for macOS. It does not prompt during restoration.
class MacosFileAccess {
  const MacosFileAccess({
    MethodChannel channel = const MethodChannel(
      'future_notes/macos_file_access',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// The previous bookmark is untouched until [MacosLibraryGrant.accept].
  Future<MacosLibraryGrant?> chooseLibrary() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'chooseLibrary',
    );
    return value == null ? null : MacosLibraryGrant._(this, value);
  }

  Future<MacosPathGrant?> chooseExportDirectory() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'chooseExportDirectory',
    );
    return value == null ? null : MacosPathGrant._(this, value);
  }

  /// Returns null only when no library has previously been accepted.
  /// Revoked, moved, missing, or mismatched access throws a [PlatformException].
  /// A caller may then offer explicit reselection while preserving its draft.
  Future<MacosLibraryGrant?> restoreLibrary({String? expectedPath}) async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'restoreLibrary',
      {'expectedPath': expectedPath},
    );
    return value == null ? null : MacosLibraryGrant._(this, value);
  }

  /// Metadata only. The caller owns each lease until processing/cancel cleanup
  /// finishes, even if its picker or other presentation has already closed.
  Future<List<MacosInputGrant>?> chooseInputs({
    bool allowMultiple = true,
    List<String>? extensions,
  }) async {
    final values = await _channel.invokeListMethod<Object?>('chooseInputs', {
      'allowMultiple': allowMultiple,
      if (extensions != null) 'extensions': extensions,
    });
    return values
        ?.map(
          (value) => MacosInputGrant._(this, value as Map<Object?, Object?>),
        )
        .toList(growable: false);
  }

  Future<List<MacosInputGrant>> retainDroppedInputs(List<String> paths) async {
    final values = await _channel.invokeListMethod<Object?>(
      'retainDroppedInputs',
      {'paths': paths},
    );
    if (values == null)
      throw const FormatException('Dropped files are unavailable.');
    return values
        .map((value) => MacosInputGrant._(this, value as Map<Object?, Object?>))
        .toList(growable: false);
  }

  /// The exact destination is authorized by NSSavePanel. This does not confer
  /// authority over arbitrary siblings or make a provider rename atomic.
  Future<MacosSaveGrant?> chooseSaveTarget({
    required String suggestedName,
  }) async {
    if (suggestedName.isEmpty ||
        suggestedName.contains('/') ||
        suggestedName.contains('\\') ||
        suggestedName.contains('\u0000')) {
      throw ArgumentError.value(suggestedName, 'suggestedName');
    }
    final value = await _channel.invokeMapMethod<String, Object?>(
      'chooseSaveTarget',
      {'suggestedName': suggestedName},
    );
    return value == null ? null : MacosSaveGrant._(this, value);
  }

  Future<String> cacheRoot() async =>
      (await _channel.invokeMethod<String>('cacheRoot'))!;

  /// Native implementation accepts only regular files inside its private cache.
  Future<void> openFile(String path) =>
      _channel.invokeMethod<void>('openFile', {'path': path});

  Future<void> revealFile(String path) =>
      _channel.invokeMethod<void>('revealFile', {'path': path});

  Future<void> revealLibraryFile(String path) =>
      _channel.invokeMethod<void>('revealLibraryFile', {'path': path});
}

/// One owner reference on a native security scope. [close] is idempotent.
/// Keep a separate acquired reference for a job that can outlive the UI owner.
class MacosAccessLease {
  MacosAccessLease._(this._access, this._leaseToken);

  final MacosFileAccess _access;
  final String _leaseToken;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _release();

  Future<void> _release() async {
    try {
      await _access._channel.invokeMethod<void>('release', {
        'leaseToken': _leaseToken,
      });
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

class MacosPathGrant extends MacosAccessLease {
  MacosPathGrant._(MacosFileAccess access, Map<Object?, Object?> value)
    : grantToken = _requiredString(value, 'grantToken'),
      path = _requiredString(value, 'path'),
      identity = _requiredString(value, 'identity'),
      super._(access, _requiredString(value, 'leaseToken'));

  /// Opaque process-local authority. It is not a bookmark or serializable path.
  final String grantToken;

  /// OS-issued filesystem path, valid while an owner/job lease is retained.
  final String path;

  /// Native device/inode identity; path text alone is not storage authority.
  final String identity;

  Future<MacosAccessLease> acquire() async {
    if (_closing != null) throw StateError('The file access owner is closed.');
    final lease = await _access._channel.invokeMethod<String>('acquire', {
      'grantToken': grantToken,
    });
    if (lease == null || lease.isEmpty) {
      throw const FormatException('Invalid native file access lease.');
    }
    return MacosAccessLease._(_access, lease);
  }
}

class MacosLibraryGrant extends MacosPathGrant {
  MacosLibraryGrant._(super.access, super.value) : super._();

  /// Call only after storage admission succeeds. The previous accepted bookmark
  /// and all of its active scopes remain valid when admission/cancellation fails.
  Future<void> accept() {
    if (_closing != null) {
      throw StateError('The library access owner is closed.');
    }
    return _access._channel.invokeMethod<void>('acceptLibrary', {
      'grantToken': grantToken,
    });
  }
}

/// The OS-issued replacement directory is on the destination volume. Only
/// this candidate belongs to the save grant; no sibling authority is assumed.
class MacosSaveGrant extends MacosPathGrant {
  MacosSaveGrant._(MacosFileAccess access, Map<Object?, Object?> value)
    : _candidate = _requiredString(value, 'candidate'),
      super._(access, value);
  String _candidate;
  String get candidate => _candidate;

  Future<String> nextCandidate() async {
    final path = await _access._channel.invokeMethod<String>(
      'nextSaveCandidate',
      {'grantToken': grantToken},
    );
    if (path == null || path.isEmpty)
      throw const FormatException('Invalid save candidate.');
    return _candidate = path;
  }

  Future<void> publish({
    required int length,
    required int modifiedMicros,
    required int changedMicros,
  }) => _access._channel.invokeMethod<void>('publishSave', {
    'grantToken': grantToken,
    'length': length,
    'modifiedMicros': modifiedMicros,
    'changedMicros': changedMicros,
  });
}

class MacosInputGrant extends MacosPathGrant {
  MacosInputGrant._(MacosFileAccess access, Map<Object?, Object?> value)
    : name = _requiredString(value, 'name'),
      length = _length(value),
      super._(access, value);

  final String name;
  final int length;
}

String _requiredString(Map<Object?, Object?> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw const FormatException('Invalid native file access response.');
  }
  return result;
}

int _length(Map<Object?, Object?> value) {
  final length = value['length'];
  if (length is! int || length < 0) {
    throw const FormatException('Invalid native file length.');
  }
  return length;
}
