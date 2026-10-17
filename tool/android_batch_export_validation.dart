// Explicit synthetic device probe. Never imported by the normal application.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';
import 'package:flutter_application_1/core/platform/mobile_export.dart';
import 'package:flutter_application_1/core/storage/external_file_export.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/posix_file_actions.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Synthetic export check'))),
    ),
  );
  final report = <String, Object?>{'passed': false, 'stage': 0};
  final paths = <String>[];
  final candidates = <String>[];
  Directory? run;
  try {
    report['stage'] = 1;
    run = await (await getTemporaryDirectory()).createTemp(
      'export-validation-',
    );
    report['stage'] = 2;
    AndroidNativeCipher.initialize(ServicesBinding.rootIsolateToken);
    if (!await AndroidNativeCipher.probe())
      throw StateError('native-unavailable');
    for (var i = 0; i < 2; i++) {
      final plain = File('${run.path}/plain-$i.txt');
      await plain.writeAsString('synthetic export payload $i');
      final encrypted = '${run.path}/encrypted-$i.med';
      report['stage'] = 3;
      await StreamingFileCipher.transform(
        source: StreamingFileSource(plain.path, await plain.length()),
        destination: encrypted,
        decryptSource: false,
        encryptDestination: true,
      );
      report['stage'] = 4;
      final destination = await MobileExport.destination('synthetic.txt');
      paths.add(destination);
      report['stage'] = 5;
      final revision = await ExternalFileExport.review(destination);
      final candidate = ExternalFileExport.candidatePath(destination);
      candidates.add(candidate);
      report['stage'] = 6;
      await StreamingFileCipher.transform(
        source: StreamingFileSource(encrypted, await File(encrypted).length()),
        destination: candidate,
        decryptSource: true,
        encryptDestination: false,
      );
      report['stage'] = 7;
      final result = await ExternalFileExport.publish(
        candidate: candidate,
        destination: destination,
        expected: revision,
      );
      report['outcome'] = result.outcome.name;
      if (!result.isSuccess) {
        final libc = DynamicLibrary.open('libc.so');
        final link = libc
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
              int Function(Pointer<Utf8>, Pointer<Utf8>)
            >('link');
        final errno = libc
            .lookupFunction<
              Pointer<Int32> Function(),
              Pointer<Int32> Function()
            >('__errno');
        final from = candidate.toNativeUtf8();
        final to = destination.toNativeUtf8();
        try {
          report['linkResult'] = link(from, to);
          report['linkErrno'] = errno().value;
        } finally {
          calloc.free(from);
          calloc.free(to);
        }
        throw StateError('publication-failed');
      }
      if (await File(destination).readAsString() !=
          'synthetic export payload $i')
        throw StateError('payload-mismatch');
      report['files'] = i + 1;
    }
    if (paths.map((path) => File(path).uri.pathSegments.last).toSet().length !=
        2) {
      throw StateError('duplicate-share-name');
    }
    report['distinctShareNames'] = true;
    if (const bool.fromEnvironment('FN_EXPORT_PROBE_SHARE')) {
      report['stage'] = 8;
      print('FN_EXPORT_PROBE_READY {"files":2}');
      report['shareAccepted'] = await MobileExport.shareAll(paths);
      final cache = Directory(
        p.join(
          await (await getTemporaryDirectory()).resolveSymbolicLinks(),
          'share_plus',
        ),
      );
      for (var i = 0; i < paths.length; i++) {
        final copy = File(p.join(cache.path, p.basename(paths[i])));
        if (await copy.readAsString() != 'synthetic export payload $i') {
          throw StateError('native-share-copy-mismatch');
        }
        await copy.delete();
      }
      report['nativeSharePayloadsVerified'] = true;
    }
    report['stage'] = 9;
    final destination = paths.first;
    final prior = await File(destination).readAsString();
    final candidate = ExternalFileExport.candidatePath(destination);
    candidates.add(candidate);
    await File(candidate).writeAsString('synthetic replacement');
    final actions = PosixFileActions(p.dirname(destination));
    final conflict = await actions.moveWithoutReplace(candidate, destination);
    if (conflict.isSuccess ||
        await File(destination).readAsString() != prior ||
        !await File(candidate).exists()) {
      throw StateError('no-replace-conflict');
    }
    final stale = await ExternalFileExport.publish(
      candidate: candidate,
      destination: destination,
      expected: const StorageRevision.missing(),
    );
    if (stale.isSuccess ||
        await File(destination).readAsString() != prior ||
        !await File(candidate).exists()) {
      throw StateError('stale-export-conflict');
    }
    final replacement = await ExternalFileExport.publish(
      candidate: candidate,
      destination: destination,
      expected: await ExternalFileExport.review(destination),
    );
    if (!replacement.isSuccess ||
        await File(destination).readAsString() != 'synthetic replacement') {
      throw StateError('replacement-publication');
    }
    final backups = await File(
      destination,
    ).parent.list().where((entry) => entry.path.endsWith('.previous')).toList();
    if (backups.length != 1 ||
        await File(backups.single.path).readAsString() != prior) {
      throw StateError('replacement-backup');
    }
    candidates.add(backups.single.path);
    report['publicationConflictAndReplacementVerified'] = true;
    report['passed'] = true;
  } catch (error) {
    report['failureType'] = error.runtimeType.toString();
    if (error is FileSystemException)
      report['osCode'] = error.osError?.errorCode;
    if (error is StateError)
      report['symlinkRejected'] =
          error.message == 'Storage locations cannot traverse links.';
    if (error is PlatformException) report['platformCode'] = error.code;
  } finally {
    for (final path in candidates) {
      if (await File(path).exists()) await File(path).delete();
    }
    await MobileExport.discardAll(paths);
    report['cleanupPassed'] = ![
      ...paths,
      ...candidates,
    ].any((path) => File(path).existsSync());
    if (run != null) await run.delete(recursive: true);
  }
  // Contains only fixed stages, numeric codes and synthetic result flags.
  print('FN_EXPORT_PROBE ${jsonEncode(report)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            report['passed'] == true
                ? 'Export check passed'
                : 'Export check failed',
          ),
        ),
      ),
    ),
  );
}
