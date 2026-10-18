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
    for (final password in <String?>[null, 'synthetic-archive']) {
      test(
        '${format.name} metadata inspection stages no attachments (password=${password != null})',
        () async {
          final fields = metadata(duplicateNames: true);
          final input = await sources();
          final file = p.join(run.path, 'preflight-package');
          final write = await operation('preflight-write');
          final read = await operation('preflight-read');
          final service = StreamingPackService();
          await service.exportPackage(
            metadata: fields,
            attachments: input,
            format: format,
            password: password,
            destination: file,
            operationDirectory: write.path,
          );
          final preview = await service.inspectPackage(
            source: file,
            password: password,
            operationDirectory: read.path,
          );
          expect(preview.note.metadata, fields);
          final staged = await read
              .list()
              .where((e) => e is File)
              .cast<File>()
              .toList();
          expect(staged, hasLength(format == ExportFormat.zip ? 1 : 0));
          expect(staged.where((f) => f.path.endsWith('.med')), isEmpty);
          final restored = await service.importPackage(
            source: file,
            metadata: preview,
            password: password,
            operationDirectory: read.path,
          );
          expect(restored.note.metadata, fields);
          for (final entry in input.entries) {
            expect(
              await File(restored.attachments[entry.key]!.path).readAsBytes(),
              await File(entry.value.path).readAsBytes(),
            );
          }
        },
      );
    }
  }

  test(
    'DEFLATE metadata preview defers attachment CRC validation until import proceeds',
    () async {
      final fields = metadata();
      final input = await sources();
      final zip = Archive()
        ..addFile(ArchiveFile.string('note.json', jsonEncode(fields)))
        ..addFile(
          ArchiveFile.string(
            'metadata.json',
            jsonEncode({'first': 'first.med', 'second': 'second.med'}),
          ),
        );
      for (final entry in input.entries) {
        zip.addFile(
          ArchiveFile(
            'attachments/${entry.key}.med',
            entry.value.length,
            await File(entry.value.path).readAsBytes(),
          ),
        );
      }
      final encoded = Uint8List.fromList(ZipEncoder().encode(zip));
      final data = ByteData.sublistView(encoded);
      var cursor = data.getUint32(encoded.length - 6, Endian.little);
      var changed = false;
      while (data.getUint32(cursor, Endian.little) == 0x02014b50) {
        final nameLength = data.getUint16(cursor + 28, Endian.little);
        final extraLength = data.getUint16(cursor + 30, Endian.little);
        final commentLength = data.getUint16(cursor + 32, Endian.little);
        final name = utf8.decode(
          encoded.sublist(cursor + 46, cursor + 46 + nameLength),
        );
        if (name.startsWith('attachments/')) {
          // Keep framing self-consistent but give the unchanged compressed
          // payload a wrong CRC. This avoids random DEFLATE error variants.
          final crc = data.getUint32(cursor + 16, Endian.little) ^ 1;
          data.setUint32(cursor + 16, crc, Endian.little);
          final local = data.getUint32(cursor + 42, Endian.little);
          data.setUint32(local + 14, crc, Endian.little);
          if ((data.getUint16(cursor + 8, Endian.little) & 8) != 0) {
            var descriptor =
                local +
                30 +
                data.getUint16(local + 26, Endian.little) +
                data.getUint16(local + 28, Endian.little) +
                data.getUint32(cursor + 20, Endian.little);
            if (data.getUint32(descriptor, Endian.little) == 0x08074b50)
              descriptor += 4;
            data.setUint32(descriptor, crc, Endian.little);
          }
          changed = true;
          break;
        }
        cursor += 46 + nameLength + extraLength + commentLength;
      }
      expect(changed, isTrue);
      final file = await File(
        p.join(run.path, 'corrupt-payload.zip'),
      ).writeAsBytes(encoded);
      final read = await operation('corrupt-preview');
      final service = StreamingPackService();
      final preview = await service.inspectPackage(
        source: file.path,
        operationDirectory: read.path,
      );
      expect(preview.note.note.id, fields['id']);
      expect(await read.list().length, 1);
      await expectLater(
        service.importPackage(
          source: file.path,
          metadata: preview,
          operationDirectory: read.path,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );
  for (final format in ExportFormat.values) {
    test(
      '${format.name} password framing preserves metadata larger than a cipher window',
      () async {
        final fields = {
          ...metadata(),
          'unknownLarge': 'x' * (2 * 1024 * 1024 + 17),
        };
        final out = p.join(run.path, 'large-${format.name}');
        final write = await operation('large-write-${format.name}');
        final receipt = await StreamingPackService().exportPackage(
          metadata: fields,
          attachments: await sources(),
          format: format,
          destination: out,
          operationDirectory: write.path,
          password: 'synthetic-archive',
        );
        expect(receipt.readbackBytes, 0);
        final read = await operation('large-read-${format.name}');
        final restored = await StreamingPackService().importPackage(
          source: out,
          operationDirectory: read.path,
          password: 'synthetic-archive',
        );
        expect(restored.note.metadata, fields);
      },
    );
  }
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
          final progress = <PackageExportProgress>[];
          await StreamingPackService().exportPackage(
            metadata: fields,
            attachments: input,
            format: format,
            destination: out.path,
            operationDirectory: write.path,
            password: password,
            onProgress: progress.add,
          );
          expect(progress, isNotEmpty);
          expect(
            progress.every(
              (event) => event.bytes >= 0 && event.bytes <= event.total,
            ),
            isTrue,
          );
          final written = progress.where(
            (event) => event.phase == PackageExportPhase.writing,
          );
          expect(
            written.any(
              (event) => event.bytes > 0 && event.bytes == event.total,
            ),
            isTrue,
          );
          expect(progress.any((event) => event.fileName == 'same.txt'), isTrue);
          if (password?.isNotEmpty == true) {
            expect(
              progress.any(
                (event) => event.phase == PackageExportPhase.encrypting,
              ),
              isTrue,
            );
            expect(
              progress.any(
                (event) =>
                    event.phase == PackageExportPhase.verifyingEncryption,
              ),
              isFalse,
            );
          }
          final importProgress = <PackageImportProgress>[];
          var finished = false;
          final decoded = await StreamingPackService().importPackage(
            source: out.path,
            operationDirectory: read.path,
            password: password,
            onProgress: (event) {
              expect(finished, isFalse);
              importProgress.add(event);
            },
          );
          finished = true;
          expect(importProgress, isNotEmpty);
          expect(
            importProgress.every(
              (e) =>
                  e.bytes >= 0 &&
                  e.bytes <= e.total &&
                  e.fileIndex > 0 &&
                  e.fileIndex <= e.fileCount,
            ),
            isTrue,
          );
          expect(importProgress.any((e) => e.bytes == 0), isTrue);
          expect(
            importProgress.any((e) => e.bytes > 0 && e.bytes == e.total),
            isTrue,
          );
          expect(
            importProgress.any((e) => e.fileName.contains('same.txt')),
            isTrue,
          );
          expect(
            importProgress.any((e) => e.phase == PackageImportPhase.decrypting),
            password?.isNotEmpty == true,
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
  for (final format in ExportFormat.values) {
    test(
      '${format.name} explicit write verification retains checked export path',
      () async {
        final input = await sources();
        final out = p.join(run.path, 'checked-${format.name}');
        final events = <PackageExportProgress>[];
        final receipt = await StreamingPackService().exportPackage(
          metadata: metadata(),
          attachments: input,
          format: format,
          destination: out,
          operationDirectory: (await operation(
            'checked-${format.name}-write',
          )).path,
          password: 'synthetic-password',
          verifyWrites: true,
          onProgress: events.add,
        );
        expect(receipt.verifyReadback, isTrue);
        expect(receipt.readbackBytes, greaterThan(receipt.length));
        expect(receipt.intermediateWriteBytes, greaterThan(0));
        expect(
          events.any((e) => e.phase == PackageExportPhase.verifyingEncryption),
          isTrue,
        );
        final decoded = await StreamingPackService().importPackage(
          source: out,
          operationDirectory: (await operation(
            'checked-${format.name}-read',
          )).path,
          password: 'synthetic-password',
          verifyWrites: true,
        );
        expect(decoded.note.metadata, metadata());
        expect(
          decoded.attachments.values.every((s) => s.receipt!.verifyReadback),
          isTrue,
        );
      },
    );
  }
  test(
    'packing progress can cancel the worker without emitting completion',
    () async {
      final input = await sources();
      final first = File(input['first']!.path);
      // Opaque attachment bytes are copied without decryption by the pack writer.
      await first.open(mode: FileMode.append).then((handle) async {
        try {
          await handle.truncate(64 * 1024 * 1024);
        } finally {
          await handle.close();
        }
      });
      input['first'] = StreamingFileSource(first.path, await first.length());
      final cancellation = File(p.join(run.path, 'cancel-packing'));
      final progress = <PackageExportProgress>[];
      await expectLater(
        StreamingPackService().exportPackage(
          metadata: metadata(),
          attachments: input,
          format: ExportFormat.binary,
          destination: p.join(run.path, 'cancelled-package'),
          operationDirectory: (await operation('cancel-write')).path,
          cancellationFile: cancellation.path,
          onProgress: (event) {
            progress.add(event);
            if (event.phase == PackageExportPhase.packing &&
                !cancellation.existsSync()) {
              cancellation.writeAsStringSync('cancel');
            }
          },
        ),
        throwsA(isA<FileJobCancelled>()),
      );
      expect(progress, isNotEmpty);
      expect(
        progress.any((event) => event.phase == PackageExportPhase.writing),
        isFalse,
      );
      expect(await first.length(), 64 * 1024 * 1024);
    },
  );
  test(
    'DEFLATE extraction reports byte progress without changing payloads',
    () async {
      final fields = metadata();
      final input = await sources();
      final zip = Archive()
        ..addFile(ArchiveFile.string('note.json', jsonEncode(fields)))
        ..addFile(
          ArchiveFile.string(
            'metadata.json',
            jsonEncode({'first': 'first.med', 'second': 'second.med'}),
          ),
        );
      for (final entry in input.entries) {
        zip.addFile(
          ArchiveFile(
            'attachments/${entry.key}.med',
            entry.value.length,
            await File(entry.value.path).readAsBytes(),
          ),
        );
      }
      final file = await File(
        p.join(run.path, 'compressed.zip'),
      ).writeAsBytes(ZipEncoder().encode(zip));
      final progress = <PackageImportProgress>[];
      final restored = await StreamingPackService().importPackage(
        source: file.path,
        operationDirectory: (await operation('deflate-read')).path,
        onProgress: progress.add,
      );
      expect(
        progress.where((e) => e.fileName == 'note.json').last.bytes,
        utf8.encode(jsonEncode(fields)).length,
      );
      expect(restored.note.metadata, fields);
      for (final entry in input.entries) {
        expect(
          await File(restored.attachments[entry.key]!.path).readAsBytes(),
          await File(entry.value.path).readAsBytes(),
        );
      }
    },
  );

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
