import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';

/// Opted into separately from fast regressions. All paths are disposable and
/// explicitly admitted; attachments are never materialized as a byte array.
void main() {
  final root = Platform.environment['FN_LARGE_STREAMING_ROOT'];
  test(
    'real 4 GiB boundary and 10 GiB cipher/ZIP64 bounded round trips',
    () async {
      if (root == null ||
          !p.isAbsolute(root) ||
          !p.basename(root).startsWith('future-notes-validation-')) {
        throw StateError('Explicit disposable large-file root required.');
      }
      if (await Directory(root).exists())
        throw StateError('Large-file root must be fresh.');
      await Directory(root).create(recursive: true);
      final results = <Map<String, dynamic>>[];
      for (final length in [
        4 * 1024 * 1024 * 1024 + 17,
        10 * 1024 * 1024 * 1024,
      ]) {
        final directory = await Directory(p.join(root, '$length')).create();
        final result = await Isolate.run(() async {
          final source = File(p.join(directory.path, 'synthetic-source'));
          final input = await source.open(mode: FileMode.writeOnly);
          try {
            await input.truncate(length);
            await input.setPosition(length - 16);
            await input.writeFrom(List.generate(16, (index) => index));
            await input.flush();
          } finally {
            await input.close();
          }
          final clock = Stopwatch()..start();
          var maxRss = ProcessInfo.currentRss;
          var lastLog = -30000;
          void progress(String phase, int bytes, int total) {
            final rss = ProcessInfo.currentRss;
            if (rss > maxRss) maxRss = rss;
            if (clock.elapsedMilliseconds - lastLog >= 30000) {
              // Synthetic byte counts only; no note data or paths.
              print('Large-file $length: $phase $bytes/$total, RSS $rss');
              lastLog = clock.elapsedMilliseconds;
            }
          }

          final encrypted = p.join(directory.path, 'synthetic.med');
          final encoded = await StreamingFileCipher.transform(
            source: StreamingFileSource(source.path, length),
            destination: encrypted,
            decryptSource: false,
            encryptDestination: true,
            progress: progress,
          );
          final decoded = await StreamingFileCipher.transform(
            source: StreamingFileSource(encrypted, encoded.length),
            destination: p.join(directory.path, 'synthetic-roundtrip'),
            decryptSource: true,
            encryptDestination: false,
            progress: progress,
          );
          if (decoded.length != length ||
              decoded.plaintextHash != encoded.plaintextHash) {
            throw StateError('Large-file round-trip mismatch.');
          }
          await source.delete();
          await File(p.join(directory.path, 'synthetic-roundtrip')).delete();
          return <String, dynamic>{
            'length': length,
            'cipherLength': encoded.length,
            'plaintextSha256': encoded.plaintextHash,
            'peakRss': maxRss,
            'milliseconds': clock.elapsedMilliseconds,
          };
        });
        results.add(result);
        // The 10 GiB payload proves ZIP64 framing independently from Dart's writer.
        if (length == 10 * 1024 * 1024 * 1024) {
          await StreamingPackService().exportPackage(
            metadata: {
              'id': 'synthetic-large',
              'title': 'Synthetic large fixture',
              'content': '[]',
              'isLocked': false,
              'timestamp': 1700000000000,
              'attachments': [
                {'id': 'large', 'fileName': 'large.bin', 'size': length},
              ],
            },
            attachments: {
              'large': StreamingFileSource(
                p.join(directory.path, 'synthetic.med'),
                result['cipherLength'] as int,
              ),
            },
            format: ExportFormat.zip,
            destination: p.join(root, 'independent-zip64.zip'),
            operationDirectory: directory.path,
          );
        } else {
          await File(p.join(directory.path, 'synthetic.med')).delete();
        }
      }
      await File(
        p.join(root, 'results.json'),
      ).writeAsString(jsonEncode(results), flush: true);
    },
    skip: root == null,
    timeout: const Timeout(Duration(hours: 2)),
  );
}
