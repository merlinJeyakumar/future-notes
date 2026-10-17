import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory('.validation/android-native-compat');
  final desktop = EncryptionService(useNative: false);
  const packages = StreamingPackService(useNative: false);
  const verify = bool.fromEnvironment('FN_NATIVE_COMPAT_VERIFY');
  test(
    verify
        ? 'desktop imports actual Android-native exports'
        : 'generate immutable desktop compatibility fixtures',
    () async {
      await root.create(recursive: true);
      if (verify) {
        final output = Directory('${root.path}/android-output');
        final manifest =
            jsonDecode(await File('${output.path}/exports.json').readAsString())
                as List;
        final summary =
            jsonDecode(await File('${output.path}/summary.json').readAsString())
                as Map;
        expect(summary['passed'], true);
        for (var i = 0; i < manifest.length; i++) {
          final record = manifest[i] as Map;
          final metadata = Map<String, dynamic>.from(record['metadata'] as Map);
          final password = record['archivePassword'] as String?;
          final directory = await Directory(
            '${root.path}/read-${DateTime.now().microsecondsSinceEpoch}-$i',
          ).create();
          final source = '${output.path}/${record['file']}';
          final imported = await packages.importPackage(
            source: source,
            operationDirectory: directory.path,
            password: password,
          );
          expect(imported.note.metadata, metadata);
          final bytes = await File(
            imported.attachments['attachment-legacy-id']!.path,
          ).readAsBytes();
          final plain = await desktop.decryptBinaryResult(
            bytes,
            password: record['notePassword'] as String?,
          );
          expect(plain.isSuccess, true);
          expect(
            sha256.convert(plain.value!).toString(),
            record['payloadHash'],
          );
          final legacy = PackService(desktop);
          final packed = await File(source).readAsBytes();
          final old = record['format'] == 'binary'
              ? await legacy.extractPack(packed, password: password)
              : await legacy.extractZipPack(packed, password: password);
          expect(old, isNotNull);
          expect(old!.metadata, metadata);
        }
        final envelope = await File(
          '${output.path}/native-note.enc',
        ).readAsString();
        final decoded = await desktop.decryptAppResult(envelope);
        expect(decoded.isSuccess, true);
        final metadata = jsonDecode(decoded.value!) as Map;
        expect(metadata['id'], 'synthetic-note-kept-id');
        expect(
          (await desktop.decryptResult(
            metadata['content'] as String,
            password: 'synthetic-note-password',
          )).value,
          '  Unicode é தமிழ்\n body  ',
        );
        expect(metadata['unknown'], {
          'nested': [1, true, 'keep'],
        });
        print(
          'NATIVE_COMPAT_DESKTOP_IMPORT_PASS ${manifest.length} packages plus encrypted note',
        );
        return;
      }
      final run = await Directory(
        '${root.path}/desktop-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final records = <Map<String, dynamic>>[];
      final payload = Uint8List.fromList(
        List.generate(1024 * 1024 + 17, (i) => i % 251),
      );
      for (final locked in [false, true]) {
        final notePassword = locked ? 'synthetic-note-password' : null;
        final attachment = await desktop.encryptBinary(
          payload,
          password: notePassword,
        );
        final fields = <String, dynamic>{
          'id': 'synthetic-note-kept-id',
          'title': 'Synthetic தமிழ்',
          'content': locked
              ? await desktop.encrypt(
                  '  Unicode é தமிழ்\n body  ',
                  password: notePassword,
                )
              : '  Unicode é தமிழ்\n body  ',
          'isLocked': locked,
          'timestamp': 1700000000000,
          'updated': 1700000000017,
          'unknown': {
            'nested': [1, true, 'keep'],
          },
          'attachments': [
            {
              'id': 'attachment-legacy-id',
              'mentionId': 'stable-mention-id',
              'fileName': 'synthetic report.bin',
              'size': payload.length,
              'custom': 'keep',
            },
          ],
        };
        for (final format in ExportFormat.values) {
          for (final archivePassword in <String?>[
            null,
            'synthetic-archive-password',
          ]) {
            final name =
                'desktop-${records.length}.${format == ExportFormat.zip ? 'zip' : 'note'}';
            final pack = PackService(desktop);
            final note = NoteModel.fromJson(fields);
            final bytes = format == ExportFormat.binary
                ? await pack.createPack(
                    note,
                    {'attachment-legacy-id': attachment},
                    password: archivePassword,
                    noteMetadata: fields,
                  )
                : await pack.createZipPack(
                    note,
                    {'attachment-legacy-id': attachment},
                    password: archivePassword,
                    noteMetadata: fields,
                  );
            await File('${run.path}/$name').writeAsBytes(bytes, flush: true);
            records.add({
              'file': name,
              'format': format.name,
              'archivePassword': archivePassword,
              'notePassword': notePassword,
              'metadata': fields,
              'payloadHash': sha256.convert(payload).toString(),
            });
          }
        }
      }
      final vectors = <Map<String, dynamic>>[];
      for (final length in [0, 1, 15, 16, 17, 1024 * 1024 + 17]) {
        for (final password in <String?>[
          null,
          '',
          'é🔒012345678901234567890123456789012345',
        ]) {
          final plain = Uint8List.fromList(
            List.generate(length, (i) => i % 239),
          );
          final file = 'vector-${vectors.length}.med';
          await File('${run.path}/$file').writeAsBytes(
            await desktop.encryptBinary(plain, password: password),
          );
          vectors.add({
            'file': file,
            'length': length,
            'password': password,
            'hash': sha256.convert(plain).toString(),
          });
        }
      }
      final block = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 251),
      );
      final hashes = <String, String>{};
      for (final length in [128, 700]) {
        final sink = _HashSink();
        final digest = sha256.startChunkedConversion(sink);
        for (var i = 0; i < length; i++) {
          digest.add(block);
        }
        digest.close();
        hashes['$length'] = sink.value!;
      }
      await File('${run.path}/manifest.json').writeAsString(
        jsonEncode({
          'packages': records,
          'vectors': vectors,
          'benchmarkHashes': hashes,
        }),
      );
      await File(
        '${root.path}/desktop-run.txt',
      ).writeAsString(run.absolute.path);
      print('NATIVE_COMPAT_FIXTURES ${run.absolute.path}');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

class _HashSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest digest) => value = digest.toString();
  @override
  void close() {}
}
