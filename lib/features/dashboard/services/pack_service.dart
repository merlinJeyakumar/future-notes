import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../models/note_model.dart';
import 'encryption_service.dart';

/// Result of extracting a pack file
class PackResult {
  final NoteModel note;
  final Map<String, Uint8List> attachments;

  PackResult({required this.note, required this.attachments});
}

/// Export format options
enum ExportFormat { binary, zip, pdf }

/// Service for creating and extracting note pack files
class PackService {
  static const List<int> _magicHeader = [0x4E, 0x4F, 0x54, 0x45]; // "NOTE"
  static const int _version = 1;
  static const int _flagEncrypted = 0x01;

  final IEncryptionService _encryptionService;

  PackService(this._encryptionService);

  /// Create a binary pack from note and attachments
  Future<Uint8List> createPack(
    NoteModel note,
    Map<String, Uint8List> attachments, {
    String? password,
  }) async {
    final builder = BytesBuilder();

    // Create payload
    final payloadBuilder = BytesBuilder();

    // Metadata (note JSON without embedded attachment data)
    final noteJson = json.encode(note.toJson());
    final noteBytes = utf8.encode(noteJson);
    payloadBuilder.add(_int32ToBytes(noteBytes.length));
    payloadBuilder.add(noteBytes);

    // Attachments
    payloadBuilder.add(_int32ToBytes(attachments.length));
    for (final entry in attachments.entries) {
      final idBytes = utf8.encode(entry.key);
      payloadBuilder.add(_int32ToBytes(idBytes.length));
      payloadBuilder.add(idBytes);
      payloadBuilder.add(_int32ToBytes(entry.value.length));
      payloadBuilder.add(entry.value);
    }

    var payload = payloadBuilder.toBytes();
    int flags = 0;

    // Encrypt if password provided
    if (password != null && password.isNotEmpty) {
      payload = await _encryptionService.encryptBinary(
        payload,
        password: password,
      );
      flags |= _flagEncrypted;
    }

    // Header
    builder.add(_magicHeader);
    builder.addByte(_version);
    builder.addByte(flags);

    // Payload
    builder.add(payload);

    return builder.toBytes();
  }

  /// Extract a binary pack to note and attachments
  Future<PackResult?> extractPack(
    Uint8List packData, {
    String? password,
  }) async {
    if (!isPack(packData)) return null;

    try {
      // Skip header (4 bytes magic + 1 byte version + 1 byte flags)
      final flags = packData[5];
      var payload = packData.sublist(6);

      // Decrypt if encrypted
      if ((flags & _flagEncrypted) != 0) {
        if (password == null || password.isEmpty) {
          return null; // Password required but not provided
        }
        payload = await _encryptionService.decryptBinary(
          payload,
          password: password,
        );
        if (payload.isEmpty) {
          return null; // Decryption failed
        }
      }

      int offset = 0;

      // Read note JSON
      final noteLength = _bytesToInt32(payload, offset);
      offset += 4;
      final noteJson = utf8.decode(
        payload.sublist(offset, offset + noteLength),
      );
      offset += noteLength;
      final note = NoteModel.fromJson(json.decode(noteJson));

      // Read attachments
      final attachmentCount = _bytesToInt32(payload, offset);
      offset += 4;

      final attachments = <String, Uint8List>{};
      for (int i = 0; i < attachmentCount; i++) {
        final idLength = _bytesToInt32(payload, offset);
        offset += 4;
        final id = utf8.decode(payload.sublist(offset, offset + idLength));
        offset += idLength;

        final dataLength = _bytesToInt32(payload, offset);
        offset += 4;
        final data = Uint8List.fromList(
          payload.sublist(offset, offset + dataLength),
        );
        offset += dataLength;

        attachments[id] = data;
      }

      return PackResult(note: note, attachments: attachments);
    } catch (e) {
      print('Error extracting pack: $e');
      return null;
    }
  }

  /// Create a ZIP pack from note and attachments
  Future<Uint8List> createZipPack(
    NoteModel note,
    Map<String, Uint8List> attachments, {
    String? password,
  }) async {
    final archive = Archive();

    // Add note.json
    final noteJson = json.encode(note.toJson());
    var noteBytes = utf8.encode(noteJson);

    // If password, encrypt the note JSON
    if (password != null && password.isNotEmpty) {
      noteBytes = await _encryptionService.encryptBinary(
        Uint8List.fromList(noteBytes),
        password: password,
      );
    }

    archive.addFile(ArchiveFile('note.json', noteBytes.length, noteBytes));

    // Add attachments
    for (final entry in attachments.entries) {
      var data = entry.value;
      if (password != null && password.isNotEmpty) {
        data = await _encryptionService.encryptBinary(data, password: password);
      }

      // Find the attachment model to get filename
      final attachment = note.attachments.firstWhere(
        (a) => a.id == entry.key,
        orElse: () => AttachmentModel(id: entry.key, fileName: entry.key),
      );
      archive.addFile(
        ArchiveFile('attachments/${attachment.fileName}', data.length, data),
      );
    }

    // Add metadata for attachment mapping
    final metadata = <String, String>{};
    for (final attachment in note.attachments) {
      metadata[attachment.id] = attachment.fileName;
    }
    final metadataJson = json.encode(metadata);
    var metadataBytes = utf8.encode(metadataJson);
    if (password != null && password.isNotEmpty) {
      metadataBytes = await _encryptionService.encryptBinary(
        Uint8List.fromList(metadataBytes),
        password: password,
      );
    }
    archive.addFile(
      ArchiveFile('metadata.json', metadataBytes.length, metadataBytes),
    );

    // Encode to ZIP in background isolate
    final zipData = await compute(_zipEncodeTask, archive);
    return zipData;
  }

  /// Extract a ZIP pack to note and attachments
  Future<PackResult?> extractZipPack(
    Uint8List zipData, {
    String? password,
  }) async {
    try {
      // Decode ZIP in background isolate
      final archive = await compute(_zipDecodeTask, zipData);

      // Find note.json
      final noteFile = archive.files.firstWhere(
        (f) => f.name == 'note.json',
        orElse: () => throw Exception('No note.json in archive'),
      );

      var noteBytes = Uint8List.fromList(noteFile.content as List<int>);

      // Decrypt if password provided
      if (password != null && password.isNotEmpty) {
        noteBytes = await _encryptionService.decryptBinary(
          noteBytes,
          password: password,
        );
        if (noteBytes.isEmpty) {
          return null; // Decryption failed
        }
      }

      final noteJson = utf8.decode(noteBytes);
      final note = NoteModel.fromJson(json.decode(noteJson));

      // Find metadata.json for attachment mapping
      Map<String, String> idToFilename = {};
      try {
        final metadataFile = archive.files.firstWhere(
          (f) => f.name == 'metadata.json',
        );
        var metadataBytes = Uint8List.fromList(
          metadataFile.content as List<int>,
        );
        if (password != null && password.isNotEmpty) {
          metadataBytes = await _encryptionService.decryptBinary(
            metadataBytes,
            password: password,
          );
        }
        final metadataJson = utf8.decode(metadataBytes);
        idToFilename = Map<String, String>.from(json.decode(metadataJson));
      } catch (_) {
        // Metadata might not exist in older exports
      }

      // Create reverse mapping
      final filenameToId = <String, String>{};
      idToFilename.forEach((id, filename) {
        filenameToId[filename] = id;
      });

      // Extract attachments
      final attachments = <String, Uint8List>{};
      for (final file in archive.files) {
        if (file.name.startsWith('attachments/') && file.isFile) {
          final filename = file.name.replaceFirst('attachments/', '');
          var data = Uint8List.fromList(file.content as List<int>);

          if (password != null && password.isNotEmpty) {
            data = await _encryptionService.decryptBinary(
              data,
              password: password,
            );
          }

          // Use the ID from metadata, or filename as fallback
          final id = filenameToId[filename] ?? filename;
          attachments[id] = data;
        }
      }

      return PackResult(note: note, attachments: attachments);
    } catch (e) {
      print('Error extracting ZIP pack: $e');
      return null;
    }
  }

  /// Check if data is a binary pack file
  bool isPack(Uint8List data) {
    if (data.length < 6) return false;
    return data[0] == _magicHeader[0] &&
        data[1] == _magicHeader[1] &&
        data[2] == _magicHeader[2] &&
        data[3] == _magicHeader[3];
  }

  /// Check if a pack file is encrypted
  bool isEncrypted(Uint8List data) {
    if (!isPack(data)) return false;
    return (data[5] & _flagEncrypted) != 0;
  }

  /// Check if data is a ZIP file
  bool isZip(Uint8List data) {
    if (data.length < 4) return false;
    // ZIP magic number: PK (0x50 0x4B 0x03 0x04)
    return data[0] == 0x50 &&
        data[1] == 0x4B &&
        data[2] == 0x03 &&
        data[3] == 0x04;
  }

  // Utility functions
  List<int> _int32ToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  int _bytesToInt32(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}

// Isolate-friendly static functions for compute()
Uint8List _zipEncodeTask(Archive archive) {
  final zipData = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipData);
}

Archive _zipDecodeTask(Uint8List data) {
  return ZipDecoder().decodeBytes(data);
}
