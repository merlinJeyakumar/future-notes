import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:archive/archive.dart' as archive;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import '../../../core/platform/android_native_cipher.dart';

import '../../../core/storage/streaming_file_cipher.dart';
import '../models/note_envelope.dart';
import 'note_codec.dart';
import 'pack_service.dart' show ExportFormat;

class FilePackResult {
  const FilePackResult(this.note, this.attachments);
  final DecodedNote note;
  final Map<String, StreamingFileSource> attachments;
}

/// Native package jobs transfer descriptors only. Stored ZIP64 export and
/// legacy stored/DEFLATE import use immediate bounded file sinks.
class StreamingPackService {
  const StreamingPackService({this.useNative = true});
  final bool useNative;
  static const metadataLimit = 32 * 1024 * 1024;
  static const directoryLimit = 64 * 1024 * 1024;
  static const entryLimit = 10000;
  static const nameLimit = 4096;
  static const _maxCipherLength = StreamingFileCipher.maxAttachmentBytes + 32;

  Future<void> exportPackage({
    required Map<String, dynamic> metadata,
    required Map<String, StreamingFileSource> attachments,
    required ExportFormat format,
    required String destination,
    required String operationDirectory,
    String? password,
    String? cancellationFile,
  }) async {
    final token = useNative && AndroidNativeCipher.ready
        ? ServicesBinding.rootIsolateToken
        : null;
    final owner = token == null ? null : const Uuid().v4();
    try {
      await Isolate.run(() {
        AndroidNativeCipher.initialize(token, owner: owner);
        return _export(
          metadata,
          attachments,
          format,
          destination,
          operationDirectory,
          password,
          cancellationFile,
        );
      });
    } finally {
      await AndroidNativeCipher.releaseOwner(owner);
    }
  }

  Future<FilePackResult> importPackage({
    required String source,
    required String operationDirectory,
    String? password,
    String? cancellationFile,
  }) async {
    final token = useNative && AndroidNativeCipher.ready
        ? ServicesBinding.rootIsolateToken
        : null;
    final owner = token == null ? null : const Uuid().v4();
    try {
      return await Isolate.run(() {
        AndroidNativeCipher.initialize(token, owner: owner);
        return _import(source, operationDirectory, password, cancellationFile);
      });
    } finally {
      await AndroidNativeCipher.releaseOwner(owner);
    }
  }

  static void _cancel(String? path) {
    if (path != null && File(path).existsSync()) throw const FileJobCancelled();
  }

  static Uint8List _u32(int n, [Endian endian = Endian.big]) =>
      (ByteData(4)..setUint32(0, n, endian)).buffer.asUint8List();
  static int _read32(
    Uint8List bytes,
    int offset, [
    Endian endian = Endian.little,
  ]) => ByteData.sublistView(bytes).getUint32(offset, endian);
  static int _read16(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint16(offset, Endian.little);
  static int _read64(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint64(offset, Endian.little);
  static void _name(String name) {
    if (name.isEmpty ||
        utf8.encode(name).length > nameLimit ||
        name.contains('\\') ||
        name.contains(':') ||
        name.startsWith('/') ||
        name.contains('\u0000') ||
        name.split('/').any((part) => part == '..' || part == '.')) {
      throw const FormatException('Invalid package name.');
    }
  }

  static Future<void> _copy(
    StreamingFileSource source,
    RandomAccessFile sink, {
    String? cancellationFile,
    int? expectedCrc,
  }) async {
    final reader = await LegacyFileReader.open(source);
    var crc = 0;
    try {
      while (reader.remaining > 0) {
        _cancel(cancellationFile);
        final bytes = await reader.read(
          min(StreamingFileCipher.window, reader.remaining),
        );
        if (expectedCrc != null) crc = _crc(bytes, crc);
        await sink.writeFrom(bytes);
      }
      if (expectedCrc != null && expectedCrc != crc) {
        throw const FormatException('Package source changed between passes.');
      }
    } finally {
      await reader.close();
    }
  }

  static Future<void> _export(
    Map<String, dynamic> metadata,
    Map<String, StreamingFileSource> attachments,
    ExportFormat format,
    String destination,
    String directory,
    String? password,
    String? cancel,
  ) async {
    final decoded = NoteCodec.decodeMetadata(jsonEncode(metadata));
    final declared = decoded.note.attachments.map((a) => a.id).toSet();
    if (attachments.length != declared.length ||
        !declared.containsAll(attachments.keys)) {
      throw const FormatException('Package attachments are incomplete.');
    }
    if (attachments.length + 2 > entryLimit) {
      throw const FormatException('Too many package entries.');
    }
    final json = Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
    if (json.length > metadataLimit) {
      throw const FormatException('Package metadata exceeds limit.');
    }
    for (final entry in attachments.entries) {
      _name(entry.key);
      if (entry.value.length < 0 || entry.value.length > _maxCipherLength) {
        throw const FormatException('Package attachment exceeds allowance.');
      }
      if (format == ExportFormat.binary && entry.value.length > 0xffffffff) {
        throw const FormatException(
          'Binary-v1 record exceeds 4 GiB. Select ZIP64.',
        );
      }
    }
    _cancel(cancel);
    if (format == ExportFormat.binary) {
      final payload = File(p.join(directory, 'binary-payload'));
      await payload.create(exclusive: true);
      final output = await payload.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(_u32(json.length));
        await output.writeFrom(json);
        await output.writeFrom(_u32(attachments.length));
        for (final entry in attachments.entries) {
          final id = utf8.encode(entry.key);
          await output.writeFrom(_u32(id.length));
          await output.writeFrom(id);
          await output.writeFrom(_u32(entry.value.length));
          await _copy(entry.value, output, cancellationFile: cancel);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      var framedSource = StreamingFileSource(
        payload.path,
        await payload.length(),
      );
      if (password != null && password.isNotEmpty) {
        final encrypted = p.join(directory, 'binary-archive.enc');
        final transformed = await StreamingFileCipher.transform(
          source: framedSource,
          destination: encrypted,
          decryptSource: false,
          encryptDestination: true,
          destinationPassword: password,
          cancelled: () => cancel != null && File(cancel).existsSync(),
          maxPlaintextBytes: 1 << 62,
        );
        framedSource = StreamingFileSource(encrypted, transformed.length);
      }
      final file = File(destination);
      await file.create(exclusive: true);
      final sink = await file.open(mode: FileMode.writeOnly);
      try {
        await sink.writeFrom([
          0x4e,
          0x4f,
          0x54,
          0x45,
          1,
          password == null || password.isEmpty ? 0 : 1,
        ]);
        await _copy(framedSource, sink, cancellationFile: cancel);
        await sink.flush();
      } finally {
        await sink.close();
      }
    } else {
      final notePath = p.join(directory, 'zip-note.json');
      await File(notePath).writeAsBytes(json, flush: true);
      final entries = <String, StreamingFileSource>{
        'note.json': StreamingFileSource(notePath, json.length),
      };
      final mapping = <String, String>{};
      for (final attachment in decoded.note.attachments) {
        final safe = attachment.fileName.replaceAll(
          RegExp(r'[\\/:<>|?*\x00-\x1f]'),
          '_',
        );
        final basename = safe.isEmpty || safe == '.' || safe == '..'
            ? 'attachment'
            : safe;
        final relative = '${attachment.id}/$basename';
        _name(relative);
        mapping[attachment.id] = relative;
        entries['attachments/$relative'] = attachments[attachment.id]!;
      }
      final mapBytes = utf8.encode(jsonEncode(mapping));
      final mappingPath = p.join(directory, 'zip-metadata.json');
      await File(mappingPath).writeAsBytes(mapBytes, flush: true);
      entries['metadata.json'] = StreamingFileSource(
        mappingPath,
        mapBytes.length,
      );
      final stored = <String, StreamingFileSource>{};
      for (final entry in entries.entries) {
        _cancel(cancel);
        if (password != null && password.isNotEmpty) {
          final encrypted = p.join(
            directory,
            '${const Uuid().v4()}.archive.enc',
          );
          final result = await StreamingFileCipher.transform(
            source: entry.value,
            destination: encrypted,
            decryptSource: false,
            encryptDestination: true,
            destinationPassword: password,
            cancelled: () => cancel != null && File(cancel).existsSync(),
            maxPlaintextBytes: _maxCipherLength,
          );
          stored[entry.key] = StreamingFileSource(encrypted, result.length);
        } else {
          stored[entry.key] = entry.value;
        }
      }
      await _writeZip64(destination, stored, cancel);
    }
    _cancel(cancel);
  }

  static Future<FilePackResult> _import(
    String source,
    String directory,
    String? password,
    String? cancel,
  ) async {
    final file = File(source);
    final handle = await file.open();
    final header = await handle.read(6);
    await handle.close();
    if (header.length < 6) {
      throw const FormatException('Truncated package header.');
    }
    if (header[0] == 0x4e &&
        header[1] == 0x4f &&
        header[2] == 0x54 &&
        header[3] == 0x45) {
      if (header[4] != 1 || (header[5] & ~1) != 0) {
        throw const FormatException('Unsupported binary package.');
      }
      final encrypted = header[5] == 1;
      if (encrypted && (password == null || password.isEmpty)) {
        throw const FormatException('Archive password required.');
      }
      final reader = await LegacyFileReader.open(
        StreamingFileSource(source, await file.length() - 6, offset: 6),
        encrypted: encrypted,
        password: password,
      );
      try {
        final jsonLength = _read32(await reader.read(4), 0, Endian.big);
        if (jsonLength > metadataLimit) {
          throw const FormatException('Package metadata exceeds limit.');
        }
        final decoded = NoteCodec.decodeMetadata(
          utf8.decode(await reader.read(jsonLength)),
        );
        final count = _read32(await reader.read(4), 0, Endian.big);
        if (count > entryLimit) {
          throw const FormatException('Too many package records.');
        }
        final attachments = <String, StreamingFileSource>{};
        for (var i = 0; i < count; i++) {
          _cancel(cancel);
          final idLength = _read32(await reader.read(4), 0, Endian.big);
          if (idLength == 0 || idLength > nameLimit) {
            throw const FormatException('Invalid package ID length.');
          }
          final id = utf8.decode(await reader.read(idLength));
          _name(id);
          if (attachments.containsKey(id)) {
            throw const FormatException('Duplicate attachment ID.');
          }
          final length = _read32(await reader.read(4), 0, Endian.big);
          final output = p.join(directory, '${const Uuid().v4()}.med');
          await reader.copyTo(
            output,
            length,
            cancelled: () => cancel != null && File(cancel).existsSync(),
          );
          attachments[id] = StreamingFileSource(output, length);
        }
        if (reader.remaining != 0) {
          throw const FormatException('Trailing binary package bytes.');
        }
        _complete(decoded, attachments);
        return FilePackResult(decoded, attachments);
      } finally {
        await reader.close();
      }
    }
    final entries = await _readZip(source, directory, cancel);
    final note = entries['note.json'];
    if (note == null) throw const FormatException('Missing package note.');
    Future<Uint8List> readMetadata(StreamingFileSource source) async {
      final reader = await LegacyFileReader.open(
        source,
        encrypted: password != null && password.isNotEmpty,
        password: password,
      );
      try {
        if (reader.remaining > metadataLimit) {
          throw const FormatException('Package metadata exceeds limit.');
        }
        return await reader.read(reader.remaining);
      } finally {
        await reader.close();
      }
    }

    final decoded = NoteCodec.decodeMetadata(
      utf8.decode(await readMetadata(note)),
    );
    final mapping = <String, String>{};
    final mappingFile = entries['metadata.json'];
    if (mappingFile != null) {
      final json = jsonDecode(utf8.decode(await readMetadata(mappingFile)));
      if (json is! Map<String, dynamic> ||
          json.values.any((v) => v is! String)) {
        throw const FormatException('Corrupt package metadata.');
      }
      mapping.addAll(json.cast<String, String>());
    }
    final payloads = <String, StreamingFileSource>{};
    final used = <String>{};
    for (final attachment in decoded.note.attachments) {
      final relative = mappingFile == null
          ? attachment.fileName
          : mapping[attachment.id];
      if (relative == null) {
        throw const FormatException('Missing attachment mapping.');
      }
      _name(relative);
      final entryName = 'attachments/$relative';
      final entry = entries[entryName];
      if (entry == null || !used.add(entryName)) {
        throw const FormatException('Missing or duplicate attachment payload.');
      }
      if (password != null && password.isNotEmpty) {
        final output = p.join(directory, '${const Uuid().v4()}.med');
        final reader = await LegacyFileReader.open(
          entry,
          encrypted: true,
          password: password,
        );
        try {
          if (reader.remaining > _maxCipherLength) {
            throw const FormatException('Oversized attachment.');
          }
          final length = reader.remaining;
          await reader.copyTo(
            output,
            length,
            cancelled: () => cancel != null && File(cancel).existsSync(),
          );
          payloads[attachment.id] = StreamingFileSource(output, length);
        } finally {
          await reader.close();
        }
      } else {
        payloads[attachment.id] = entry;
      }
    }
    if (entries.keys
        .where((k) => k.startsWith('attachments/'))
        .any((key) => !used.contains(key))) {
      throw const FormatException('Undeclared package attachments.');
    }
    if (mappingFile != null &&
        (mapping.length != payloads.length ||
            !payloads.keys.toSet().containsAll(mapping.keys))) {
      throw const FormatException('Inconsistent package mapping.');
    }
    _complete(decoded, payloads);
    return FilePackResult(decoded, payloads);
  }

  static void _complete(
    DecodedNote note,
    Map<String, StreamingFileSource> attachments,
  ) {
    final expected = note.note.attachments.map((a) => a.id).toSet();
    if (expected.length != attachments.length ||
        !expected.containsAll(attachments.keys)) {
      throw const FormatException('Incomplete package.');
    }
  }

  static Future<void> _writeZip64(
    String destination,
    Map<String, StreamingFileSource> entries,
    String? cancel,
  ) async {
    final file = File(destination);
    await file.create(exclusive: true);
    final output = await file.open(mode: FileMode.writeOnly);
    final records = <_ZipEntry>[];
    Future<void> number(int n, int width) => output.writeFrom(
      (width == 2
              ? (ByteData(2)..setUint16(0, n, Endian.little))
              : width == 4
              ? (ByteData(4)..setUint32(0, n, Endian.little))
              : (ByteData(8)..setUint64(0, n, Endian.little)))
          .buffer
          .asUint8List(),
    );
    try {
      for (final entry in entries.entries) {
        _cancel(cancel);
        _name(entry.key);
        final crc = await _fileCrc(entry.value, cancel);
        final offset = await output.position();
        final bytes = utf8.encode(entry.key);
        await number(0x04034b50, 4);
        await number(45, 2);
        await number(0x800, 2);
        await number(0, 2);
        await number(0, 2);
        await number(33, 2);
        await number(crc, 4);
        await number(0xffffffff, 4);
        await number(0xffffffff, 4);
        await number(bytes.length, 2);
        await number(20, 2);
        await output.writeFrom(bytes);
        await number(1, 2);
        await number(16, 2);
        await number(entry.value.length, 8);
        await number(entry.value.length, 8);
        await _copy(
          entry.value,
          output,
          cancellationFile: cancel,
          expectedCrc: crc,
        );
        records.add(
          _ZipEntry(
            entry.key,
            0x800,
            0,
            crc,
            entry.value.length,
            entry.value.length,
            offset,
          ),
        );
      }
      final directoryStart = await output.position();
      for (final record in records) {
        final bytes = utf8.encode(record.name);
        await number(0x02014b50, 4);
        await number(45, 2);
        await number(45, 2);
        await number(0x800, 2);
        await number(0, 2);
        await number(0, 2);
        await number(33, 2);
        await number(record.crc, 4);
        await number(0xffffffff, 4);
        await number(0xffffffff, 4);
        await number(bytes.length, 2);
        await number(28, 2);
        await number(0, 2);
        await number(0, 2);
        await number(0, 2);
        await number(0, 4);
        await number(0xffffffff, 4);
        await output.writeFrom(bytes);
        await number(1, 2);
        await number(24, 2);
        await number(record.size, 8);
        await number(record.compressed, 8);
        await number(record.offset, 8);
      }
      final end = await output.position();
      if (end - directoryStart > directoryLimit) {
        throw const FormatException('ZIP directory exceeds limit.');
      }
      await number(0x06064b50, 4);
      await number(44, 8);
      await number(45, 2);
      await number(45, 2);
      await number(0, 4);
      await number(0, 4);
      await number(records.length, 8);
      await number(records.length, 8);
      await number(end - directoryStart, 8);
      await number(directoryStart, 8);
      await number(0x07064b50, 4);
      await number(0, 4);
      await number(end, 8);
      await number(1, 4);
      await number(0x06054b50, 4);
      await number(0, 2);
      await number(0, 2);
      await number(0xffff, 2);
      await number(0xffff, 2);
      await number(0xffffffff, 4);
      await number(0xffffffff, 4);
      await number(0, 2);
      await output.flush();
    } finally {
      await output.close();
    }
  }

  static Future<int> _fileCrc(
    StreamingFileSource source,
    String? cancel,
  ) async {
    final reader = await LegacyFileReader.open(source);
    var crc = 0;
    try {
      while (reader.remaining > 0) {
        _cancel(cancel);
        crc = _crc(
          await reader.read(min(reader.remaining, StreamingFileCipher.window)),
          crc,
        );
      }
    } finally {
      await reader.close();
    }
    return crc;
  }

  static final _crcTable = List.generate(256, (n) {
    var c = n;
    for (var i = 0; i < 8; i++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  static int _crc(List<int> bytes, int initial) {
    var crc = initial ^ 0xffffffff;
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 255] ^ (crc >> 8);
    }
    return crc ^ 0xffffffff;
  }

  static void _verifyDeflateConsumption(
    String source,
    int start,
    _ZipEntry record,
    String? cancel,
  ) {
    final file = archive.InputFileStream(
      source,
      bufferSize: StreamingFileCipher.window,
    );
    try {
      final input = _DeflateInput(file, start, record.compressed, cancel);
      final sink = _DeflateHistory(record.size, cancel);
      archive.Inflate.stream(input, output: sink);
      if (input.position != record.compressed ||
          sink.length != record.size ||
          sink.crc != record.crc) {
        throw const FormatException(
          'DEFLATE framing is incomplete or contains unconsumed bytes.',
        );
      }
    } finally {
      file.closeSync();
    }
  }

  static Future<Map<String, StreamingFileSource>> _readZip(
    String source,
    String directory,
    String? cancel,
  ) async {
    final file = File(source);
    final before = await file.stat();
    final input = await file.open();
    Future<Uint8List> at(int offset, int count) async {
      if (offset < 0 ||
          count < 0 ||
          offset + count > before.size ||
          count > directoryLimit) {
        throw const FormatException('ZIP bounds invalid.');
      }
      await input.setPosition(offset);
      final bytes = await input.read(count);
      if (bytes.length != count) throw const FormatException('Truncated ZIP.');
      return bytes;
    }

    try {
      final tailLength = min(before.size, 65557);
      final tail = await at(before.size - tailLength, tailLength);
      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (_read32(tail, i) == 0x06054b50 &&
            i + 22 + _read16(tail, i + 20) == tail.length) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) throw const FormatException('ZIP end record missing.');
      if (_read16(tail, eocd + 4) != 0 || _read16(tail, eocd + 6) != 0) {
        throw const FormatException('Multipart ZIP unsupported.');
      }
      var count = _read16(tail, eocd + 10);
      var length = _read32(tail, eocd + 12);
      var offset = _read32(tail, eocd + 16);
      final eocdOffset = before.size - tailLength + eocd;
      var directoryEnd = eocdOffset;
      if (count == 0xffff || length == 0xffffffff || offset == 0xffffffff) {
        final locator = await at(eocdOffset - 20, 20);
        if (_read32(locator, 0) != 0x07064b50 ||
            _read32(locator, 4) != 0 ||
            _read32(locator, 16) != 1) {
          throw const FormatException('Invalid ZIP64 locator.');
        }
        directoryEnd = _read64(locator, 8);
        final zip64 = await at(directoryEnd, 56);
        if (_read32(zip64, 0) != 0x06064b50 ||
            _read64(zip64, 4) != 44 ||
            _read32(zip64, 16) != 0 ||
            _read32(zip64, 20) != 0 ||
            directoryEnd + 56 != eocdOffset - 20 ||
            _read64(zip64, 24) != _read64(zip64, 32)) {
          throw const FormatException('Invalid ZIP64 end record.');
        }
        count = _read64(zip64, 32);
        length = _read64(zip64, 40);
        offset = _read64(zip64, 48);
      } else if (_read16(tail, eocd + 8) != count) {
        throw const FormatException('Inconsistent ZIP count.');
      }
      if (count > entryLimit ||
          length > directoryLimit ||
          offset + length != directoryEnd) {
        throw const FormatException('ZIP metadata exceeds its bounds.');
      }
      final records = <_ZipEntry>[];
      final names = <String>{};
      var cursor = offset;
      for (var i = 0; i < count; i++) {
        final header = await at(cursor, 46);
        if (_read32(header, 0) != 0x02014b50) {
          throw const FormatException('Invalid ZIP central record.');
        }
        final flags = _read16(header, 8), method = _read16(header, 10);
        if ((flags & ~0x808) != 0 ||
            ![0, 8].contains(method) ||
            _read16(header, 34) != 0 ||
            ((_read32(header, 38) >> 16) & 0xf000) == 0xa000) {
          throw const FormatException('Unsupported ZIP entry.');
        }
        final n = _read16(header, 28),
            extraLength = _read16(header, 30),
            comment = _read16(header, 32);
        if (n == 0 ||
            n > nameLimit ||
            cursor + 46 + n + extraLength + comment > offset + length) {
          throw const FormatException('Invalid ZIP name bounds.');
        }
        final nameBytes = await at(cursor + 46, n);
        final name = utf8.decode(nameBytes);
        _name(name);
        if (!names.add(name)) {
          throw const FormatException('Duplicate ZIP path.');
        }
        var compressed = _read32(header, 20),
            size = _read32(header, 24),
            local = _read32(header, 42);
        final extra = await at(cursor + 46 + n, extraLength);
        var x = 0;
        var found = false;
        while (x < extra.length) {
          if (x + 4 > extra.length) {
            throw const FormatException('Truncated ZIP extra field.');
          }
          final kind = _read16(extra, x), sizeX = _read16(extra, x + 2);
          x += 4;
          if (x + sizeX > extra.length) {
            throw const FormatException('Invalid ZIP extra field.');
          }
          if (kind == 1) {
            if (found) {
              throw const FormatException('Duplicate ZIP64 extra field.');
            }
            found = true;
            var field = x;
            int take() {
              if (field + 8 > x + sizeX) {
                throw const FormatException('Truncated ZIP64 field.');
              }
              final value = _read64(extra, field);
              field += 8;
              return value;
            }

            if (size == 0xffffffff) size = take();
            if (compressed == 0xffffffff) compressed = take();
            if (local == 0xffffffff) local = take();
          }
          x += sizeX;
        }
        if (compressed == 0xffffffff ||
            size == 0xffffffff ||
            local == 0xffffffff ||
            compressed < 0 ||
            size < 0 ||
            local < 0 ||
            size > _maxCipherLength + 32 ||
            local >= offset) {
          throw const FormatException('Invalid ZIP entry bounds.');
        }
        if ((name == 'note.json' || name == 'metadata.json') &&
            size > metadataLimit + 32) {
          throw const FormatException('ZIP metadata exceeds limit.');
        }
        records.add(
          _ZipEntry(
            name,
            flags,
            method,
            _read32(header, 16),
            compressed,
            size,
            local,
          ),
        );
        cursor += 46 + n + extraLength + comment;
      }
      if (cursor != offset + length) {
        throw const FormatException('Trailing ZIP directory data.');
      }
      records.sort((a, b) => a.offset.compareTo(b.offset));
      var consumed = 0;
      final result = <String, StreamingFileSource>{};
      for (final record in records) {
        _cancel(cancel);
        if (record.offset != consumed) {
          throw const FormatException(
            'ZIP entries overlap or have unconsumed data.',
          );
        }
        final header = await at(record.offset, 30);
        if (_read32(header, 0) != 0x04034b50 ||
            _read16(header, 6) != record.flags ||
            _read16(header, 8) != record.method) {
          throw const FormatException('ZIP local header mismatch.');
        }
        final n = _read16(header, 26), extra = _read16(header, 28);
        if (n > nameLimit ||
            utf8.decode(await at(record.offset + 30, n)) != record.name) {
          throw const FormatException('ZIP filename mismatch.');
        }
        final start = record.offset + 30 + n + extra;
        consumed = start + record.compressed;
        if (consumed > offset) {
          throw const FormatException(
            'ZIP payload exceeds directory boundary.',
          );
        }
        if ((record.flags & 8) != 0) {
          final bytes = await at(consumed, min(24, offset - consumed));
          var position = _read32(bytes, 0) == 0x08074b50 ? 4 : 0;
          if (_read32(bytes, position) != record.crc) {
            throw const FormatException('ZIP descriptor CRC mismatch.');
          }
          position += 4;
          final wide =
              record.size >= 0xffffffff || record.compressed >= 0xffffffff;
          final compressed = wide
              ? _read64(bytes, position)
              : _read32(bytes, position);
          position += wide ? 8 : 4;
          final size = wide
              ? _read64(bytes, position)
              : _read32(bytes, position);
          position += wide ? 8 : 4;
          if (compressed != record.compressed || size != record.size) {
            throw const FormatException('ZIP descriptor size mismatch.');
          }
          consumed += position;
        }
        if (record.name.endsWith('/')) {
          if (record.size != 0) {
            throw const FormatException('Nonempty ZIP directory.');
          }
          continue;
        }
        if (record.name != 'note.json' &&
            record.name != 'metadata.json' &&
            !record.name.startsWith('attachments/')) {
          throw const FormatException('Unknown package entry.');
        }
        final outputPath = p.join(directory, '${const Uuid().v4()}.record');
        if (record.method == 8) {
          _verifyDeflateConsumption(source, start, record, cancel);
        }
        final outputFile = File(outputPath);
        await outputFile.create(exclusive: true);
        final output = outputFile.openSync(mode: FileMode.writeOnly);
        final sink = _ExpandedSink(output, record.size, record.crc);
        final Sink<List<int>>? inflater = record.method == 8
            ? ZLibDecoder(raw: true).startChunkedConversion(sink)
            : null;
        try {
          await input.setPosition(start);
          var left = record.compressed;
          while (left > 0) {
            _cancel(cancel);
            // 1 KiB compressed input bounds a worst-case DEFLATE expansion
            // window; outputs are written immediately instead of collected.
            final bytes = await input.read(
              min(left, record.method == 8 ? 1024 : StreamingFileCipher.window),
            );
            if (bytes.isEmpty) {
              throw const FormatException('Truncated ZIP payload.');
            }
            left -= bytes.length;
            if (inflater != null) {
              inflater.add(bytes);
            } else {
              sink.add(bytes);
            }
          }
          if (inflater != null) {
            inflater.close();
          } else {
            sink.close();
          }
          output.flushSync();
        } finally {
          output.closeSync();
        }
        result[record.name] = StreamingFileSource(outputPath, record.size);
      }
      if (consumed != offset) {
        throw const FormatException('Unconsumed ZIP local data.');
      }
      final after = await file.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        throw const FormatException('Package changed during import.');
      }
      return result;
    } finally {
      await input.close();
    }
  }
}

class _ZipEntry {
  const _ZipEntry(
    this.name,
    this.flags,
    this.method,
    this.crc,
    this.compressed,
    this.size,
    this.offset,
  );
  final String name;
  final int flags;
  final int method;
  final int crc;
  final int compressed;
  final int size;
  final int offset;
}

class _DeflateInput extends archive.InputFileStream {
  _DeflateInput(
    archive.InputFileStream source,
    int start,
    int length,
    this.cancel,
  ) : super.fromFileStream(source, position: start, length: length);
  final String? cancel;
  @override
  int readByte() {
    if ((position & 1023) == 0) StreamingPackService._cancel(cancel);
    return super.readByte();
  }
}

/// Immediate grammar-verification sink. Retain only DEFLATE's 32 KiB history,
/// never the expanded entry. The native decoder separately checks validity and
/// writes the entry through its bounded file sink.
class _DeflateHistory extends archive.OutputStream {
  _DeflateHistory(this.expected, this.cancel)
    : super(byteOrder: archive.ByteOrder.littleEndian);
  final int expected;
  final String? cancel;
  final _history = Uint8List(32768);
  int _count = 0;
  int _crcState = 0xffffffff;
  @override
  int get length => _count;
  int get crc => _crcState ^ 0xffffffff;
  @override
  void writeByte(int value) {
    if ((_count & 32767) == 0) StreamingPackService._cancel(cancel);
    if (_count >= expected)
      throw const FormatException('DEFLATE expanded size exceeds declaration.');
    _history[_count & 32767] = value;
    _crcState =
        StreamingPackService._crcTable[(_crcState ^ value) & 255] ^
        (_crcState >> 8);
    _count++;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    for (var i = 0; i < (length ?? bytes.length); i++) {
      writeByte(bytes[i]);
    }
  }

  @override
  void writeStream(archive.InputStream stream) {
    while (!stream.isEOS) {
      writeBytes(stream.readBytes(min(32768, stream.length)).toUint8List());
    }
  }

  @override
  Uint8List subset(int start, [int? end]) {
    if (start < 0) start += _count;
    end = end == null
        ? _count
        : end < 0
        ? _count + end
        : end;
    if (start < max(0, _count - 32768) || end > _count || end < start) {
      throw const FormatException('Invalid DEFLATE history reference.');
    }
    return Uint8List.fromList(
      List.generate(end - start, (i) => _history[(start + i) & 32767]),
    );
  }

  @override
  void flush() {}
  @override
  void clear() => throw UnsupportedError(
    'A history verifier cannot discard earlier output.',
  );
}

class _ExpandedSink implements Sink<List<int>> {
  _ExpandedSink(this.output, this.expected, this.expectedCrc);
  final RandomAccessFile output;
  final int expected;
  final int expectedCrc;
  int length = 0;
  int crc = 0;
  @override
  void add(List<int> bytes) {
    length += bytes.length;
    if (length > expected) {
      throw const FormatException('ZIP expanded size exceeds declaration.');
    }
    crc = StreamingPackService._crc(bytes, crc);
    output.writeFromSync(bytes);
  }

  @override
  void close() {
    if (length != expected || crc != expectedCrc) {
      throw const FormatException('ZIP size or CRC mismatch.');
    }
  }
}
