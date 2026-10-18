import 'dart:io';
import 'package:flutter/services.dart';

import 'library_documents.dart';

/// Android SAF and iOS coordinated document access share this control protocol.
/// Payload messages are bounded; the selected provider remains authoritative.
class MobileLibraryDocuments
    implements LibraryDocuments, LibraryCapacity, LibraryOutputSinks {
  const MobileLibraryDocuments({
    required this.kind,
    MethodChannel channel = const MethodChannel('future_notes/documents'),
  }) : _channel = channel;

  final LibraryLocationKind kind;
  final MethodChannel _channel;

  @override
  Future<LibraryOutputSinkLease> openOutputSink(
    LibraryLocation library,
    LibraryDocument parent,
    String name,
  ) async {
    // The Apple adapter currently coordinates bounded transfers, not a held
    // streaming writer. Keep the one-transfer encrypted fallback on that path.
    if (kind != LibraryLocationKind.androidTree) {
      throw const LibraryAccessException(
        'unsupported_sink',
        'A direct output sink is unavailable.',
      );
    }
    validateDocumentName(name);
    final value = (await _invoke<Map<Object?, Object?>>('openOutputSink', {
      ..._args(library, parent),
      'name': name,
    }))!;
    return LibraryOutputSinkLease(
      library: library,
      parent: parent,
      document: LibraryDocument.fromJson(
        value['document'] as Map<Object?, Object?>,
      ),
      lease: value['lease'] as String,
      path: value['path'] as String,
    );
  }

  @override
  Future<LibraryDocument> checkOutputSink(LibraryOutputSinkLease sink) async =>
      LibraryDocument.fromJson(
        (await _invoke<Map<Object?, Object?>>('checkOutputSink', {
          ..._args(sink.library, sink.document),
          'lease': sink.lease,
          'path': sink.path,
        }))!,
      );

  @override
  Future<void> closeOutputSink(LibraryOutputSinkLease sink) => _invoke<void>(
    'closeOutputSink',
    {..._args(sink.library, sink.document), 'lease': sink.lease},
  );

  @override
  Future<int?> availableBytes(
    LibraryLocation library,
    LibraryDocument document,
  ) async => Platform.isAndroid
      ? _invoke<int>('availableBytes', _args(library, document))
      : null;

  Future<NativeDocumentSource> openSource(
    LibraryLocation library,
    LibraryDocument document,
  ) async {
    final value = (await _invoke<Map<Object?, Object?>>(
      'openSource',
      _args(library, document),
    ))!;
    return NativeDocumentSource(
      value['lease'] as String,
      value['path'] as String,
      value['length'] as int,
      value['identity'] as String,
    );
  }

  Future<void> closeSource(LibraryLocation library, String lease) =>
      _invoke<void>('closeSource', {..._args(library), 'lease': lease});

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw LibraryAccessException(
        error.code,
        error.message ?? 'Selected folder access failed.',
      );
    }
  }

  Map<String, Object?> _args(
    LibraryLocation library, [
    LibraryDocument? document,
  ]) {
    if (library.kind != kind || kind == LibraryLocationKind.fileSystem) {
      throw const LibraryAccessException(
        'wrong_backend',
        'This library belongs to another storage adapter.',
      );
    }
    return {'library': library.token, 'document': document?.token};
  }

  @override
  Future<LibraryLocation?> selectLocalFolder() async {
    final token = await _invoke<String>('selectLocalFolder', {});
    return token == null ? null : LibraryLocation(kind: kind, token: token);
  }

  @override
  Future<LibraryDocument> root(LibraryLocation library) async =>
      LibraryDocument.fromJson(
        (await _invoke<Map<Object?, Object?>>('root', _args(library)))!,
      );

  @override
  Future<LibraryDocument> stat(
    LibraryLocation library,
    LibraryDocument document,
  ) async => LibraryDocument.fromJson(
    (await _invoke<Map<Object?, Object?>>('stat', _args(library, document)))!,
  );

  @override
  Future<List<LibraryDocument>> children(
    LibraryLocation library,
    LibraryDocument parent,
  ) async => (await _invoke<List<Object?>>('children', _args(library, parent)))!
      .map((value) => LibraryDocument.fromJson(value as Map<Object?, Object?>))
      .toList(growable: false);

  @override
  Future<LibraryDocument> create(
    LibraryLocation library,
    LibraryDocument parent,
    String name, {
    bool directory = false,
  }) async {
    validateDocumentName(name);
    return LibraryDocument.fromJson(
      (await _invoke<Map<Object?, Object?>>('create', {
        ..._args(library, parent),
        'name': name,
        'directory': directory,
      }))!,
    );
  }

  @override
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  }) async {
    validateDocumentRange(offset, length);
    final result = (await _invoke<Uint8List>('read', {
      ..._args(library, document),
      'offset': offset,
      'length': length,
    }))!;
    if (result.length > length) {
      throw const LibraryAccessException(
        'invalid_read',
        'Invalid provider read.',
      );
    }
    return result;
  }

  @override
  Future<void> append(
    LibraryLocation library,
    LibraryDocument document,
    Uint8List bytes, {
    required int offset,
  }) async {
    validateDocumentRange(offset, bytes.length);
    await _invoke<void>('append', {
      ..._args(library, document),
      'offset': offset,
      'bytes': bytes,
    });
  }

  @override
  Future<void> flush(LibraryLocation library, LibraryDocument document) async {
    await _invoke<void>('flush', _args(library, document));
  }

  @override
  Future<LibraryDocument> rename(
    LibraryLocation library,
    LibraryDocument document,
    String name,
  ) async {
    validateDocumentName(name);
    return LibraryDocument.fromJson(
      (await _invoke<Map<Object?, Object?>>('rename', {
        ..._args(library, document),
        'name': name,
      }))!,
    );
  }

  @override
  Future<void> delete(LibraryLocation library, LibraryDocument document) async {
    await _invoke<void>('delete', _args(library, document));
  }
}

class NativeDocumentSource {
  const NativeDocumentSource(this.lease, this.path, this.length, this.identity);
  final String lease;

  /// An opened native descriptor capability, never derived from a provider URI.
  final String path;
  final int length;
  final String identity;
}
