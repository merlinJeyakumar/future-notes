import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';

void main() {
  final rootPath = Platform.environment['FN_LARGE_OPEN_CACHE_ROOT'];
  test(
    '4 GiB and 10 GiB explicit Open caches bounded plaintext and reuses it',
    () async {
      if (rootPath == null ||
          !p.isAbsolute(rootPath) ||
          !p.basename(rootPath).startsWith('future-notes-validation-')) {
        throw StateError('Explicit disposable cache test root required.');
      }
      final root = Directory(rootPath);
      if (await root.exists()) {
        throw StateError('Large cache test directory must be fresh.');
      }
      await root.create(recursive: true);
      final records = <Map<String, dynamic>>[];
      for (final size in [
        4 * 1024 * 1024 * 1024 + 17,
        10 * 1024 * 1024 * 1024,
      ]) {
        final result = await Isolate.run(() async {
          final folder = await Directory(p.join(rootPath, '$size')).create();
          final input = File(p.join(folder.path, 'synthetic-source'));
          final out = await input.open(mode: FileMode.writeOnly);
          await out.truncate(size);
          await out.close();
          final encrypted = p.join(folder.path, 'synthetic.med');
          await StreamingFileCipher.transform(
            source: StreamingFileSource(input.path, size),
            destination: encrypted,
            decryptSource: false,
            encryptDestination: true,
          );
          final cacheFolder = await Directory(
            p.join(folder.path, 'cache'),
          ).create();
          final binding = StorageBinding(folder.path, 0);
          final note = NoteReference(
            binding: binding,
            fileName: 'synthetic',
            format: NoteStorageFormat.folder,
            contentPath: binding.child('synthetic.enc'),
            attachmentLocation: folder.path,
          );
          final model = AttachmentModel(
            id: 'synthetic',
            fileName: 'demo-video.mp4',
            size: size,
          );
          final cache = AttachmentOpenCache(
            rootResolver: () async => cacheFolder.path,
            sourceResolver: (_, id) async =>
                StreamingFileSource(encrypted, await File(encrypted).length()),
          );
          final clock = Stopwatch()..start();
          var peak = ProcessInfo.currentRss;
          var last = -30000;
          final opened = await cache.prepare(
            note,
            model,
            0,
            onProgress: (phase, bytes, total) {
              peak = max(peak, ProcessInfo.currentRss);
              if (clock.elapsedMilliseconds - last >= 30000) {
                last = clock.elapsedMilliseconds;
                stdout.writeln(
                  'Open cache $size: $phase $bytes/$total; RSS $peak',
                );
              }
            },
          );
          if (!opened.isSuccess) {
            throw StateError(
              'Large cache Open failed (${opened.outcome.name}).',
            );
          }
          final sourceHash = await sha256.bind(input.openRead()).first;
          final openedHash = await sha256
              .bind(File(opened.value!.path).openRead())
              .first;
          if (sourceHash != openedHash) {
            throw StateError('Large cache payload mismatch.');
          }
          final reopened = await cache.prepare(note, model, 0);
          if (!reopened.isSuccess ||
              reopened.value!.path != opened.value!.path ||
              cache.transformCount != 1) {
            throw StateError('Cache hit decrypted again.');
          }
          final row = {
            'length': size,
            'sha256': sourceHash.toString(),
            'transformCount': cache.transformCount,
            'peakRss': peak,
            'elapsedMs': clock.elapsedMilliseconds,
          };
          await cache.invalidateNote(note);
          if (await File(opened.value!.path).exists()) {
            throw StateError('Cache plaintext retained unexpectedly.');
          }
          await cache.close();
          await File(encrypted).delete();
          await input.delete();
          return row;
        });
        records.add(result);
        await File(
          p.join(rootPath, 'results.json'),
        ).writeAsString(jsonEncode(records), flush: true);
      }
      expect(records.length, 2);
    },
    skip: rootPath == null,
    timeout: const Timeout(Duration(hours: 2)),
  );
}
