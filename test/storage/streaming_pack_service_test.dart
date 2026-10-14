import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  final encryption = EncryptionService();
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
  });
  tearDown(() => deleteValidationRun(run));
  Map<String, dynamic> metadata({bool duplicateNames = false}) => {
    'id': 'synthetic-note',
    'title': 'Synthetic package',
    'content': '  Synthetic body\n ',
    'isLocked': false,
    'timestamp': 1700000000000,
    'unknown': {'retained': true},
    'attachments': [
      {
        'id': 'first',
        'fileName': 'same.txt',
        'size': 3,
        'custom': 'first extra',
      },
      {
        'id': 'second',
        'fileName': duplicateNames ? 'same.txt' : 'second.txt',
        'size': 3,
      },
    ],
  };
  Future<Map<String, StreamingFileSource>> sources() async {
    final result = <String, StreamingFileSource>{};
    for (final id in ['first', 'second']) {
      final data = await encryption.encryptBinary(
        Uint8List.fromList(id == 'first' ? [1, 2, 3] : [4, 5, 6]),
      );
      final file = File(p.join(run.path, '$id.med'));
      await file.writeAsBytes(data);
      result[id] = StreamingFileSource(file.path, data.length);
    }
    return result;
  }

  Future<Directory> operation(String name) =>
      Directory(p.join(run.path, name)).create();
  for (final format in ExportFormat.values) {
    for (final password in <String?>[null, '', 'synthetic-archive-password']) {
      test(
        '${format.name} file-backed round trip with archive password $password',
        () async {
          final input = await sources();
          final fields = metadata();
          final out = File(p.join(run.path, 'package'));
          final write = await operation('write');
          final read = await operation('read');
          await StreamingPackService().exportPackage(
            metadata: fields,
            attachments: input,
            format: format,
            destination: out.path,
            operationDirectory: write.path,
            password: password,
          );
          final decoded = await StreamingPackService().importPackage(
            source: out.path,
            operationDirectory: read.path,
            password: password,
          );
          expect(decoded.note.metadata, fields);
          for (final id in input.keys) {
            expect(
              await File(decoded.attachments[id]!.path).readAsBytes(),
              await File(input[id]!.path).readAsBytes(),
            );
          }
          final oldReader = PackService(encryption);
          final bytes = await out.readAsBytes();
          final legacy = format == ExportFormat.binary
              ? await oldReader.extractPack(bytes, password: password)
              : await oldReader.extractZipPack(bytes, password: password);
          expect(legacy, isNotNull);
          expect(legacy!.metadata, fields);
          expect(legacy.attachments.keys.toSet(), input.keys.toSet());
        },
      );
    }
  }
  test('ZIP64 keeps duplicate display filenames distinct', () async {
    final input = await sources();
    final fields = metadata(duplicateNames: true);
    final out = File(p.join(run.path, 'duplicates.zip'));
    await StreamingPackService().exportPackage(
      metadata: fields,
      attachments: input,
      format: ExportFormat.zip,
      destination: out.path,
      operationDirectory: (await operation('write')).path,
    );
    final decoded = await StreamingPackService().importPackage(
      source: out.path,
      operationDirectory: (await operation('read')).path,
    );
    expect(decoded.note.note.attachments.map((a) => a.fileName), [
      'same.txt',
      'same.txt',
    ]);
    expect(decoded.attachments.keys.toSet(), {'first', 'second'});
    final archive = ZipDecoder().decodeBytes(await out.readAsBytes());
    expect(
      archive.files.map((f) => f.name),
      containsAll([
        'attachments/first/same.txt',
        'attachments/second/same.txt',
      ]),
    );
  });
  test(
    'DEFLATE record rejects trailing bytes despite matching expanded CRC and size',
    () async {
      final fields = {...metadata(), 'attachments': []};
      final bytes = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('note.json', jsonEncode(fields))),
        ),
      );
      final header = ByteData.sublistView(bytes);
      expect(header.getUint16(8, Endian.little), 8);
      expect(header.getUint16(6, Endian.little) & 8, 0);
      final compressed = header.getUint32(18, Endian.little);
      final eocd = bytes.length - 22;
      final directory = header.getUint32(eocd + 16, Endian.little);
      final changed = Uint8List.fromList([
        ...bytes.sublist(0, directory),
        0,
        ...bytes.sublist(directory),
      ]);
      final changedHeader = ByteData.sublistView(changed);
      changedHeader.setUint32(18, compressed + 1, Endian.little);
      changedHeader.setUint32(
        directory + 1 + 20,
        compressed + 1,
        Endian.little,
      );
      changedHeader.setUint32(eocd + 1 + 16, directory + 1, Endian.little);
      final file = File(p.join(run.path, 'trailing-deflate.zip'));
      await file.writeAsBytes(changed, flush: true);
      await expectLater(
        StreamingPackService().importPackage(
          source: file.path,
          operationDirectory: (await operation('read')).path,
        ),
        throwsFormatException,
      );
    },
  );

  test('legacy DEFLATE ZIP imports with CRC validation', () async {
    final input = await sources();
    final fields = metadata();
    final archive = Archive()
      ..addFile(ArchiveFile.string('note.json', jsonEncode(fields)))
      ..addFile(
        ArchiveFile.string(
          'metadata.json',
          jsonEncode({'first': 'same.txt', 'second': 'second.txt'}),
        ),
      );
    for (final attachment in NoteModel.fromJson(fields).attachments) {
      final bytes = await File(input[attachment.id]!.path).readAsBytes();
      archive.addFile(
        ArchiveFile('attachments/${attachment.fileName}', bytes.length, bytes),
      );
    }
    final file = File(p.join(run.path, 'legacy.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    final result = await StreamingPackService().importPackage(
      source: file.path,
      operationDirectory: (await operation('read')).path,
    );
    expect(result.note.metadata, fields);
    expect(result.attachments.length, 2);
  });
  test(
    'missing attachment rejects export before destination creation',
    () async {
      final input = await sources();
      input.remove('second');
      final destination = p.join(run.path, 'missing.zip');
      await expectLater(
        StreamingPackService().exportPackage(
          metadata: metadata(),
          attachments: input,
          format: ExportFormat.zip,
          destination: destination,
          operationDirectory: (await operation('write')).path,
        ),
        throwsFormatException,
      );
      expect(await File(destination).exists(), isFalse);
    },
  );
  test(
    'oversized binary-v1 attachment rejects before replacing a destination',
    () async {
      final existing = File(p.join(run.path, 'existing'));
      await existing.writeAsString('keep');
      final input = await sources();
      input['first'] = StreamingFileSource(input['first']!.path, 0x100000000);
      await expectLater(
        StreamingPackService().exportPackage(
          metadata: metadata(),
          attachments: input,
          format: ExportFormat.binary,
          destination: existing.path,
          operationDirectory: (await operation('write')).path,
        ),
        throwsFormatException,
      );
      expect(await existing.readAsString(), 'keep');
    },
  );
  test(
    'wrong archive password rejects before a canonical note can be published',
    () async {
      final out = File(p.join(run.path, 'locked'));
      await StreamingPackService().exportPackage(
        metadata: metadata(),
        attachments: await sources(),
        format: ExportFormat.binary,
        destination: out.path,
        operationDirectory: (await operation('write')).path,
        password: 'correct-synthetic',
      );
      await expectLater(
        StreamingPackService().importPackage(
          source: out.path,
          operationDirectory: (await operation('read')).path,
          password: 'wrong-synthetic',
        ),
        throwsFormatException,
      );
    },
  );
  test('trailing binary bytes and missing records reject import', () async {
    final out = File(p.join(run.path, 'binary'));
    await StreamingPackService().exportPackage(
      metadata: metadata(),
      attachments: await sources(),
      format: ExportFormat.binary,
      destination: out.path,
      operationDirectory: (await operation('write')).path,
    );
    await out.writeAsBytes([7], mode: FileMode.append);
    await expectLater(
      StreamingPackService().importPackage(
        source: out.path,
        operationDirectory: (await operation('read')).path,
      ),
      throwsFormatException,
    );
  });
  test(
    'corrupt present ZIP mapping never falls back to old filename mapping',
    () async {
      final fields = metadata();
      final archive = Archive()
        ..addFile(ArchiveFile.string('note.json', jsonEncode(fields)))
        ..addFile(ArchiveFile.string('metadata.json', 'broken JSON'));
      final file = File(p.join(run.path, 'corrupt.zip'));
      await file.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(
        StreamingPackService().importPackage(
          source: file.path,
          operationDirectory: (await operation('read')).path,
        ),
        throwsFormatException,
      );
    },
  );
  test('preexisting cancellation prevents package output', () async {
    final cancel = File(p.join(run.path, 'cancel'));
    await cancel.writeAsString('cancel');
    final output = p.join(run.path, 'cancelled');
    await expectLater(
      StreamingPackService().exportPackage(
        metadata: metadata(),
        attachments: await sources(),
        format: ExportFormat.binary,
        destination: output,
        operationDirectory: (await operation('write')).path,
        cancellationFile: cancel.path,
      ),
      throwsA(isA<FileJobCancelled>()),
    );
    expect(await File(output).exists(), isFalse);
  });
}
