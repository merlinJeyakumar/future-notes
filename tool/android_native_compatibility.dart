// Isolated, explicit validation target. Never imported by the shipped app.
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';
import 'package:flutter_application_1/core/platform/worker_compute_clock.dart';
import 'package:flutter_application_1/core/storage/preparation_pacer.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/core/storage/attachment_transform_worker.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_application_1/core/storage/provider_document_io.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart'
    show PreparedAttachmentFile;
import 'package:flutter_application_1/core/storage/attachment_scheduler.dart';
import 'package:flutter_application_1/core/platform/system_capacity.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_file_actions.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';

void check(bool value, String code) {
  if (!value) throw StateError(code);
}

class _ScopedDocuments extends MobileLibraryDocuments {
  _ScopedDocuments(this.scope) : super(kind: LibraryLocationKind.androidTree);
  final LibraryDocument scope;
  @override
  Future<LibraryDocument> root(LibraryLocation library) async => scope;
}

class _LocalPayload implements BoundedByteSource {
  _LocalPayload(this.file, this.length);
  final File file;
  @override
  final int length;
  @override
  Stream<List<int>> open() => file.openRead();
}

Future<_ScopedDocuments> isolatedDocuments(
  LibraryLocation location,
  Directory output,
  String label,
) async {
  const base = MobileLibraryDocuments(kind: LibraryLocationKind.androidTree);
  final scope = await base.create(
    location,
    await base.root(location),
    '.future-notes-validation-${const Uuid().v4()}',
    directory: true,
  );
  await File(
    '${output.path}/scope-$label.json',
  ).writeAsString(jsonEncode({'name': scope.name, 'token': scope.token}));
  return _ScopedDocuments(scope);
}

/// Only new synthetic note identities; never open an existing note.
Future<void> validateDirectProviderWrites(Directory output) async {
  final selection = await MobileFileActions.channel.invokeMethod<String>(
    'readLibrarySelection',
  );
  check(selection != null, 'direct-provider-selection');
  final location = LibraryLocation.fromJson(
    Map<String, Object?>.from(
      (jsonDecode(selection!) as Map)['location'] as Map,
    ),
  );
  final documents = await isolatedDocuments(location, output, 'direct');
  final source = File('${output.path}/direct-source.bin');
  await source.writeAsBytes(
    List.generate(2 * 1024 * 1024 + 17, (i) => i % 251),
  );
  for (final verify in [false, true]) {
    final files = ProviderNoteFiles(
      documents: documents,
      location: location,
      libraryId: const Uuid().v4(),
      privateRoot: await MobileFileActions().privateRoot(),
    );
    final reference = await files.newNoteReference(const Uuid().v4());
    await File('${output.path}/synthetic-note-$verify.json').writeAsString(
      jsonEncode({'id': reference.modelId, 'fileName': reference.fileName}),
    );
    final operation = await files.createOperationDirectory(reference);
    final scheduler = AttachmentScheduler(
      sample: () => const SystemCapacity(
        processors: 4,
        availableBytes: 128 * 1024 * 1024,
        systemCpu: 0,
        processCpu: 0,
      ),
    );
    final worker = AttachmentTransformWorker(scheduler: scheduler);
    try {
      final id = const Uuid().v4();
      final target = await files.createAttachmentCandidate(
        reference,
        id,
        operation,
        await source.length() + 32,
      );
      check(target.sink != null, 'direct-output-sink');
      final result = await worker
          .submit(
            FileTransformRequest(
              source: StreamingFileSource(source.path, await source.length()),
              destination: target.path,
              decryptSource: false,
              encryptDestination: true,
              destinationPassword: 'synthetic-direct-password',
              verifyOutput: verify,
              ownedTarget: target,
            ),
          )
          .result;
      check(result.isSuccess, 'direct-transform-${result.outcome.name}');
      final receipt = result.value!.receipt!;
      check(
        receipt.payloadReadBytes == await source.length() &&
            receipt.readbackBytes == (verify ? receipt.length : 0),
        'direct-pass-count',
      );
      final fields = <String, dynamic>{
        'id': reference.modelId,
        'title': 'Synthetic only',
        'content': '[]',
        'timestamp': 1700000000000,
        'isLocked': false,
        'attachments': [
          {
            'id': id,
            'fileName': 'synthetic.bin',
            'size': await source.length(),
            'mentionId': 'synthetic-stable-mention',
          },
        ],
      };
      final content = await EncryptionService().encryptApp(jsonEncode(fields));
      final committed = await files.commitGeneration(reference, content, [
        PreparedAttachmentFile(
          id,
          StreamingFileSource(target.path, receipt.length, receipt: receipt),
        ),
      ]);
      final captured = await files.attachmentSource(
        committed,
        id,
        verifyContent: false,
      );
      final decoded = await StreamingFileCipher.transform(
        source: captured,
        destination: '${output.path}/direct-$verify.bin',
        decryptSource: true,
        encryptDestination: false,
        sourcePassword: 'synthetic-direct-password',
        verifyOutput: false,
      );
      check(
        decoded.plaintextHash == result.value!.plaintextHash,
        'direct-published-payload',
      );
      final dartDecoded = await StreamingFileCipher.transform(
        source: captured,
        destination: '${output.path}/direct-dart-$verify.bin',
        decryptSource: true,
        encryptDestination: false,
        sourcePassword: 'synthetic-direct-password',
        verifyOutput: false,
        useNative: false,
      );
      check(
        dartDecoded.plaintextHash == result.value!.plaintextHash,
        'dart-provider-readable',
      );
      final largeFields = {
        ...fields,
        'largeSyntheticMetadata': 'x' * (2 * 1024 * 1024 + 17),
      };
      final largeOutput = '${output.path}/large-metadata-$verify.fnote';
      final largeOperation = await Directory(
        '${output.path}/large-metadata-$verify',
      ).create();
      await StreamingPackService().exportPackage(
        metadata: largeFields,
        attachments: {id: captured},
        format: ExportFormat.binary,
        destination: largeOutput,
        operationDirectory: largeOperation.path,
        password: 'synthetic-archive',
      );
      final largeImported = await StreamingPackService().importPackage(
        source: largeOutput,
        operationDirectory: largeOperation.path,
        password: 'synthetic-archive',
      );
      check(
        largeImported.note.metadata['largeSyntheticMetadata'] ==
            largeFields['largeSyntheticMetadata'],
        'large-native-metadata',
      );
      // Exercise strict legacy DEFLATE parsing from an actual SAF grant in
      // both native-enabled and Dart-only background workers.
      final legacyCipher = EncryptionService(useNative: false);
      final encryptedFixture = await legacyCipher.encryptBinary(
        await source.readAsBytes(),
        password: 'synthetic-direct-password',
      );
      final zip = await PackService(legacyCipher).createZipPack(
        NoteModel.fromJson(fields),
        {id: encryptedFixture},
        password: 'synthetic-archive',
        noteMetadata: fields,
      );
      final zipFile = File('${output.path}/granted-$verify.zip');
      await zipFile.writeAsBytes(zip, flush: true);
      final zipDoc = await documents.create(
        location,
        documents.scope,
        'granted-$verify.zip',
      );
      await files.io.write(
        zipDoc,
        _LocalPayload(zipFile, zip.length),
        verifyReadback: false,
        expectedHash: sha256.convert(zip).toString(),
      );
      final zipSource = await documents.openSource(location, zipDoc);
      try {
        for (final native in [true, false]) {
          final dir = await Directory(
            '${output.path}/granted-$verify-$native',
          ).create();
          final imported = await StreamingPackService(useNative: native)
              .importPackage(
                source: zipSource.path,
                operationDirectory: dir.path,
                password: 'synthetic-archive',
              );
          check(
            imported.note.metadata['id'] == fields['id'],
            'granted-import-identity',
          );
          check(
            imported.attachments[id]!.receipt!.sha256Hex ==
                sha256.convert(encryptedFixture).toString(),
            'granted-import-native-$native',
          );
        }
      } finally {
        await documents.closeSource(location, zipSource.lease);
      }
      await documents.delete(location, zipDoc);
      await AndroidNativeCipher.configure(
        AttachmentPerformance.defaults.copyWith(maxParallel: 2),
      );
      try {
        final simultaneous = await Future.wait(
          List.generate(
            2,
            (i) => StreamingFileCipher.transform(
              source: captured,
              destination: '${output.path}/parallel-$verify-$i.bin',
              decryptSource: true,
              encryptDestination: false,
              sourcePassword: 'synthetic-direct-password',
              verifyOutput: false,
            ),
          ),
        );
        check(
          simultaneous.every(
            (r) => r.plaintextHash == result.value!.plaintextHash,
          ),
          'independent-provider-cursors',
        );
      } finally {
        await AndroidNativeCipher.configure(AttachmentPerformance.defaults);
      }
      await files.releaseAttachmentSources(committed);
      final deleted = await files.deleteResolved(committed);
      check(
        deleted.isSuccess,
        'direct-synthetic-cleanup-${deleted.outcome.name}',
      );
    } finally {
      await worker.close();
      await scheduler.close();
      await files.removeOperationDirectory(operation);
      // A failed first write can leave only our freshly-created empty folders.
      final metadata = await files.io.resolve([
        reference.fileName,
        'note_content_${reference.modelId}.enc',
      ]);
      if (metadata != null) {
        final synthetic = await files.resolveNote(reference.fileName);
        if (synthetic != null) {
          await files.releaseAttachmentSources(synthetic);
          final cleanup = await files.deleteResolved(synthetic);
          if (!cleanup.isSuccess)
            await File('${output.path}/cleanup-$verify.json').writeAsString(
              jsonEncode({
                'outcome': cleanup.outcome.name,
                'message': cleanup.message,
              }),
            );
        }
      }
      if (metadata == null) {
        final folder = await files.io.resolve([reference.fileName]);
        if (folder != null) {
          final attachments = await files.io.child(folder, 'attachments');
          if (attachments != null &&
              (await documents.children(location, attachments)).isEmpty)
            await documents.delete(location, attachments);
          if ((await documents.children(location, folder)).isEmpty)
            await documents.delete(location, folder);
        }
      }
      await files.close();
    }
  }
  await source.delete();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Synthetic native compatibility validation')),
      ),
    ),
  );
  final summary = <String, dynamic>{'passed': false};
  Directory? output;
  try {
    check(await AndroidNativeCipher.probe(), 'native-provider-unavailable');
    AndroidNativeCipher.initialize(ServicesBinding.rootIsolateToken);
    final root = (await getExternalStorageDirectory())!;
    final inbox = Directory('${root.path}/crypto-validation/inbox');
    output = await Directory(
      '${root.path}/crypto-validation/output-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    summary['outputName'] = output.path.split('/').last;
    await validateDirectProviderWrites(output);
    summary['directProviderWrites'] = true;
    await validateProviderOpen(output);
    summary['providerCacheOpenAndReopen'] = true;
    final manifest =
        jsonDecode(await File('${inbox.path}/manifest.json').readAsString())
            as Map;
    final cipher = EncryptionService();
    final oracle = EncryptionService(useNative: false);
    final packages = manifest['packages'] as List;
    final exports = <Map<String, dynamic>>[];
    for (var i = 0; i < packages.length; i++) {
      final record = Map<String, dynamic>.from(packages[i] as Map);
      final directory = await Directory('${output.path}/read-$i').create();
      final imported = await const StreamingPackService().importPackage(
        source: '${inbox.path}/${record['file']}',
        operationDirectory: directory.path,
        password: record['archivePassword'] as String?,
      );
      check(
        jsonEncode(imported.note.metadata) == jsonEncode(record['metadata']),
        'package-metadata-$i',
      );
      final fields = imported.note.metadata;
      check(fields['id'] == 'synthetic-note-kept-id', 'uid-$i');
      check(
        imported.note.note.attachments.single.mentionId == 'stable-mention-id',
        'mention-$i',
      );
      final med = imported.attachments['attachment-legacy-id']!;
      final plain = '${directory.path}/plain.bin';
      final decrypted = await StreamingFileCipher.transform(
        source: med,
        destination: plain,
        decryptSource: true,
        encryptDestination: false,
        sourcePassword: record['notePassword'] as String?,
        verifyOutput: false,
      );
      check(
        decrypted.plaintextHash == record['payloadHash'],
        'desktop-attachment-$i',
      );
      final fresh = '${directory.path}/native.med';
      await StreamingFileCipher.transform(
        source: StreamingFileSource(plain, await File(plain).length()),
        destination: fresh,
        decryptSource: false,
        encryptDestination: true,
        destinationPassword: record['notePassword'] as String?,
      );
      final write = await Directory('${output.path}/write-$i').create();
      final format = record['format'] == 'binary'
          ? ExportFormat.binary
          : ExportFormat.zip;
      final file =
          'native-$i.${format == ExportFormat.binary ? 'note' : 'zip'}';
      await const StreamingPackService().exportPackage(
        metadata: fields,
        attachments: {
          'attachment-legacy-id': StreamingFileSource(
            fresh,
            await File(fresh).length(),
          ),
        },
        format: format,
        destination: '${output.path}/$file',
        operationDirectory: write.path,
        password: record['archivePassword'] as String?,
      );
      exports.add({...record, 'file': file});
    }
    var vectors = 0;
    for (final raw in manifest['vectors'] as List) {
      final record = raw as Map;
      final file = File('${inbox.path}/${record['file']}');
      final bytes = await file.readAsBytes();
      final plain = await cipher.decryptBinaryResult(
        bytes,
        password: record['password'] as String?,
      );
      check(
        plain.isSuccess && plain.value!.length == record['length'],
        'buffer-vector',
      );
      check(
        sha256.convert(plain.value!).toString() == record['hash'],
        'buffer-hash',
      );
      final native = await cipher.encryptBinary(
        plain.value!,
        password: record['password'] as String?,
      );
      final old = await oracle.decryptBinaryResult(
        native,
        password: record['password'] as String?,
      );
      check(
        old.isSuccess &&
            sha256.convert(old.value!).toString() == record['hash'],
        'native-buffer-to-desktop',
      );
      final out = '${output.path}/stream-$vectors';
      final result = await StreamingFileCipher.transform(
        source: StreamingFileSource(file.path, bytes.length),
        destination: out,
        decryptSource: true,
        encryptDestination: false,
        sourcePassword: record['password'] as String?,
        verifyOutput: false,
        expectedPlaintextBytes: record['length'] as int,
      );
      check(result.plaintextHash == record['hash'], 'stream-vector');
      vectors++;
    }
    final content = await cipher.encrypt(
      '  Unicode é தமிழ்\n body  ',
      password: 'synthetic-note-password',
    );
    final envelope = {
      'id': 'synthetic-note-kept-id',
      'title': 'Synthetic',
      'content': content,
      'isLocked': true,
      'timestamp': 1700000000000,
      'unknown': {
        'nested': [1, true, 'keep'],
      },
    };
    final sealed = await cipher.encryptApp(jsonEncode(envelope));
    check(
      (await oracle.decryptAppResult(sealed)).value == jsonEncode(envelope),
      'native-note-to-desktop',
    );
    final oldSealed = await oracle.encryptApp(jsonEncode(envelope));
    check(
      (await cipher.decryptAppResult(oldSealed)).value == jsonEncode(envelope),
      'desktop-note-to-native',
    );
    await File('${output.path}/native-note.enc').writeAsString(sealed);
    await File(
      '${output.path}/exports.json',
    ).writeAsString(jsonEncode(exports));

    // Error/cancellation paths use only this isolated synthetic directory.
    final small = File('${output.path}/source.bin');
    await small.writeAsBytes(List.generate(1024 * 1024, (i) => i % 251));
    final sentinel = File('${output.path}/sentinel');
    await sentinel.writeAsString('retained');
    try {
      await StreamingFileCipher.transform(
        source: StreamingFileSource(small.path, await small.length()),
        destination: sentinel.path,
        decryptSource: false,
        encryptDestination: true,
      );
      throw StateError('overwrite-accepted');
    } on FileSystemException {
      check(await sentinel.readAsString() == 'retained', 'overwrite-modified');
    }
    var cancelled = false;
    final cancelledPath = '${output.path}/cancelled.med';
    try {
      await StreamingFileCipher.transform(
        source: StreamingFileSource(small.path, await small.length()),
        destination: cancelledPath,
        decryptSource: false,
        encryptDestination: true,
        duty: () => 0,
        cancelled: () => cancelled,
        progress: (_, _, _) => cancelled = true,
      );
      throw StateError('cancel-not-acknowledged');
    } on FileJobCancelled {
      check(!await File(cancelledPath).exists(), 'cancel-output-retained');
    }
    final good = File('${output.path}/good.med');
    await StreamingFileCipher.transform(
      source: StreamingFileSource(small.path, await small.length()),
      destination: good.path,
      decryptSource: false,
      encryptDestination: true,
      destinationPassword: 'test',
    );
    final invalid = File('${output.path}/invalid.med');
    final broken = await good.readAsBytes();
    broken[broken.length - 1] ^= 255;
    await invalid.writeAsBytes(broken);
    for (final variant in ['padding', 'length', 'hash']) {
      final target = File('${output.path}/bad-$variant');
      try {
        await StreamingFileCipher.transform(
          source: StreamingFileSource(
            variant == 'padding' ? invalid.path : good.path,
            await good.length(),
            sha256Hex: variant == 'hash' ? '0' * 64 : null,
          ),
          destination: target.path,
          decryptSource: true,
          encryptDestination: false,
          sourcePassword: 'test',
          expectedPlaintextBytes: variant == 'length' ? 4 : null,
          verifyOutput: false,
        );
        throw StateError('invalid-$variant-accepted');
      } on FormatException {
        check(!await target.exists(), 'invalid-$variant-published');
      }
    }
    // Production isolate/token/control path, including rekey with no plaintext
    // intermediate and interruption while the native handle is owned.
    final scheduler = AttachmentScheduler(
      sample: () => const SystemCapacity(
        processors: 8,
        availableBytes: 128 * 1024 * 1024,
        systemCpu: 0,
        processCpu: 0,
        detected: false,
        workerBytes: 16 * 1024 * 1024,
      ),
    );
    final worker = AttachmentTransformWorker(scheduler: scheduler);
    final workerCipher = '${output.path}/worker.med';
    final workerWrite = await worker
        .submit(
          FileTransformRequest(
            source: StreamingFileSource(small.path, await small.length()),
            destination: workerCipher,
            decryptSource: false,
            encryptDestination: true,
            destinationPassword: 'before',
          ),
        )
        .result;
    check(workerWrite.isSuccess, 'worker-native-write');
    final rekey = '${output.path}/rekey.med';
    final rekeyed = await worker
        .submit(
          FileTransformRequest(
            source: StreamingFileSource(
              workerCipher,
              await File(workerCipher).length(),
            ),
            destination: rekey,
            decryptSource: true,
            encryptDestination: true,
            sourcePassword: 'before',
            destinationPassword: 'after',
          ),
        )
        .result;
    check(rekeyed.isSuccess, 'worker-native-rekey');
    final oldRekey = await oracle.decryptBinaryResult(
      await File(rekey).readAsBytes(),
      password: 'after',
    );
    check(
      oldRekey.isSuccess &&
          sha256.convert(oldRekey.value!).toString() ==
              workerWrite.value!.plaintextHash,
      'desktop-rekey',
    );
    await worker.close();
    await scheduler.close();

    final orphanPath = '${output.path}/orphan.med';
    final owner = const Uuid().v4();
    final token = ServicesBinding.rootIsolateToken;
    final smallPath = small.path;
    final smallLength = await small.length();
    try {
      await Isolate.run(() async {
        AndroidNativeCipher.initialize(token, owner: owner);
        final owned = Completer<void>();
        unawaited(
          StreamingFileCipher.transform(
            source: StreamingFileSource(smallPath, smallLength),
            destination: orphanPath,
            decryptSource: false,
            encryptDestination: true,
            duty: () => 0,
            progress: (phase, _, _) {
              if (phase == 'Encrypting' && !owned.isCompleted) owned.complete();
            },
          ),
        );
        await owned.future;
        throw StateError('synthetic-worker-exit');
      });
    } on StateError catch (error) {
      check(error.message == 'synthetic-worker-exit', 'worker-exit');
    } finally {
      await AndroidNativeCipher.releaseOwner(owner);
    }
    check(!await File(orphanPath).exists(), 'orphan-handle-not-joined');

    var mutated = false;
    var released = false;
    final mutation = File('${output.path}/mutation-source.bin');
    await mutation.writeAsBytes(blockForMutation());
    final mutationTarget = File('${output.path}/mutation.med');
    try {
      await StreamingFileCipher.transform(
        source: StreamingFileSource(mutation.path, await mutation.length()),
        destination: mutationTarget.path,
        decryptSource: false,
        encryptDestination: true,
        duty: () => released ? 1 : 0,
        progress: (phase, _, _) {
          if (!mutated && phase == 'Encrypting') {
            mutated = true;
            mutation
                .writeAsBytes([99], mode: FileMode.append, flush: true)
                .then((_) => released = true);
          }
        },
      );
      throw StateError('source-race-accepted');
    } on FormatException {
      check(mutated && !await mutationTarget.exists(), 'source-race-output');
    }
    final benchmarkMiB = 700;
    final block = Uint8List.fromList(
      List.generate(1024 * 1024, (i) => i % 251),
    );
    final large = File('${output.path}/benchmark.bin');
    final sink = await large.open(mode: FileMode.writeOnly);
    try {
      for (var i = 0; i < benchmarkMiB; i++) {
        await sink.writeFrom(block);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final enc = File('${output.path}/benchmark.med');
    final dec = File('${output.path}/benchmark-open.bin');
    final watch = Stopwatch()..start();
    final encrypted = await StreamingFileCipher.transform(
      source: StreamingFileSource(large.path, await large.length()),
      destination: enc.path,
      decryptSource: false,
      encryptDestination: true,
      destinationPassword: 'synthetic-benchmark',
      duty: () => .7,
    );
    final encryptionMs = watch.elapsedMilliseconds;
    final fastPath = '${output.path}/benchmark-fast.med';
    final fastOwner = const Uuid().v4();
    final fastToken = ServicesBinding.rootIsolateToken;
    final largePath = large.path;
    final largeLength = await large.length();
    watch.reset();
    final fast = await Isolate.run(() async {
      AndroidNativeCipher.initialize(fastToken, owner: fastOwner);
      return StreamingFileCipher.transform(
        source: StreamingFileSource(largePath, largeLength),
        destination: fastPath,
        decryptSource: false,
        encryptDestination: true,
        destinationPassword: 'synthetic-benchmark',
        verifyOutput: false,
        ownedTarget: OwnedWriteTarget.forPath(fastPath),
        duty: () => .7,
      );
    });
    await AndroidNativeCipher.releaseOwner(fastOwner);
    final fastEncryptionMs = watch.elapsedMilliseconds;
    check(
      fast.plaintextHash == encrypted.plaintextHash &&
          fast.receipt!.readbackBytes == 0,
      'fast-native-compat',
    );
    await File(fastPath).delete();
    summary['nativeEncryptFastMs'] = fastEncryptionMs;
    summary['nativeFastReadBytes'] = fast.receipt!.payloadReadBytes;
    summary['nativeFastReadbackBytes'] = fast.receipt!.readbackBytes;
    watch.reset();
    final opened = await StreamingFileCipher.transform(
      source: StreamingFileSource(enc.path, await enc.length()),
      destination: dec.path,
      decryptSource: true,
      encryptDestination: false,
      sourcePassword: 'synthetic-benchmark',
      verifyOutput: false,
      duty: () => .7,
    );
    final decryptionMs = watch.elapsedMilliseconds;
    check(
      encrypted.plaintextHash == manifest['benchmarkHashes']['$benchmarkMiB'] &&
          opened.plaintextHash == encrypted.plaintextHash,
      'large-hash',
    );
    // Same implementation reference, same 70% duty, smaller synthetic sample.
    final baseline = File('${output.path}/baseline.bin');
    final baselineSink = await baseline.open(mode: FileMode.writeOnly);
    try {
      for (var i = 0; i < 4; i++) {
        await baselineSink.writeFrom(block);
      }
    } finally {
      await baselineSink.close();
    }
    final compute = WorkerComputeClock();
    final pacer = PreparationPacer(
      workedMicros: compute.take,
      duty: () => .7,
      cancelled: () => false,
    );
    watch.reset();
    await StreamingFileCipher.transform(
      source: StreamingFileSource(baseline.path, await baseline.length()),
      destination: '${output.path}/baseline.med',
      decryptSource: false,
      encryptDestination: true,
      verifyOutput: true,
      cooperate: pacer.cooperate,
      beginCompute: compute.begin,
      endCompute: compute.end,
      useNative: false,
    );
    final baselineMs = watch.elapsedMilliseconds;
    compute.close();
    summary.addAll({
      'passed': true,
      'packagesEachWay': packages.length,
      'vectors': vectors,
      'failureChecks': 6,
      'workerIsolateAndRekey': true,
      'unexpectedWorkerExitJoined': true,
      'benchmarkMiB': benchmarkMiB,
      'nativeEncryptVerifiedMs': encryptionMs,
      'nativeDecryptMs': decryptionMs,
      'dartEncryptVerifiedMiB': 4,
      'dartEncryptVerifiedMs': baselineMs,
    });
    for (final file in [
      large,
      enc,
      dec,
      baseline,
      File('${output.path}/baseline.med'),
    ]) {
      await file.delete();
    }
  } catch (error) {
    summary['failureType'] = error.runtimeType.toString();
    // These are synthetic validation labels, never live user paths/content.
    if (error is StateError) summary['failureCode'] = error.message;
  }
  if (output != null)
    await File(
      '${output.path}/summary.json',
    ).writeAsString(jsonEncode(summary), flush: true);
  // ADB collects only this synthetic summary; no live library is initialized.
  print('FN_NATIVE_COMPAT ${jsonEncode(summary)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            summary['passed'] == true
                ? 'Native compatibility checks passed'
                : 'Native compatibility checks failed',
          ),
        ),
      ),
    ),
  );
}

Uint8List blockForMutation() => Uint8List(1024 * 1024);

/// Reproduce the real SAF -> ProviderNoteFiles -> worker -> native -> cache
/// path. Only UUID-named synthetic children are written, then removed. Never
/// initialize discovery/recovery or open any existing note in the selected tree.
Future<void> validateProviderOpen(Directory output) async {
  final selection = await MobileFileActions.channel.invokeMethod<String>(
    'readLibrarySelection',
  );
  check(selection != null, 'provider-selection-required');
  final location = LibraryLocation.fromJson(
    Map<String, Object?>.from(
      (jsonDecode(selection!) as Map)['location'] as Map,
    ),
  );
  final documents = await isolatedDocuments(location, output, 'cache');
  final files = ProviderNoteFiles(
    documents: documents,
    location: location,
    libraryId: const Uuid().v4(),
    privateRoot: await MobileFileActions().privateRoot(),
  );
  final created = <LibraryDocument>[];
  AttachmentOpenCache? cache;
  Directory? cacheRoot;
  try {
    final noteId = const Uuid().v4();
    final attachmentId = const Uuid().v4();
    final root = await documents.root(location);
    final note = await documents.create(
      location,
      root,
      'note_$noteId',
      directory: true,
    );
    created.add(note);
    final metadata = await documents.create(
      location,
      note,
      'note_content_$noteId.enc',
    );
    created.add(metadata);
    await documents.append(
      location,
      metadata,
      Uint8List.fromList(utf8.encode('synthetic validation only')),
      offset: 0,
    );
    final attachments = await documents.create(
      location,
      note,
      'attachments',
      directory: true,
    );
    created.add(attachments);
    final doc = await documents.create(
      location,
      attachments,
      '$attachmentId.med',
    );
    created.add(doc);
    final plain = File('${output.path}/provider-plain.bin');
    final block = Uint8List.fromList(
      List<int>.generate(1024 * 1024, (i) => i % 251),
    );
    final sink = await plain.open(mode: FileMode.writeOnly);
    try {
      for (var i = 0; i < 16; i++) {
        await sink.writeFrom(block);
      }
    } finally {
      await sink.close();
    }
    final encrypted = File('${output.path}/provider.med');
    final result = await StreamingFileCipher.transform(
      source: StreamingFileSource(plain.path, await plain.length()),
      destination: encrypted.path,
      decryptSource: false,
      encryptDestination: true,
      destinationPassword: 'synthetic-provider-password',
    );
    var offset = 0;
    await for (final bytes in encrypted.openRead()) {
      await documents.append(
        location,
        doc,
        Uint8List.fromList(bytes),
        offset: offset,
      );
      offset += bytes.length;
    }
    await documents.flush(location, doc);
    final reference = (await files.resolveNote('note_$noteId'))!;
    final attachment = AttachmentModel(
      id: attachmentId,
      fileName: 'synthetic-video.mp4',
      size: await plain.length(),
    );
    cacheRoot = await Directory(
      await MobileFileActions().privateRoot(),
    ).createTemp('cipher-validation-cache-');
    final cachePath = await cacheRoot.resolveSymbolicLinks();
    cache = AttachmentOpenCache(
      rootResolver: () async => cachePath,
      sourceResolver: files.attachmentSource,
      sourcePreparer: files.attachmentSource,
      sourceValidator: files.isAttachmentSourceCurrent,
    );
    final first = await cache.prepare(
      reference,
      attachment,
      1,
      password: 'synthetic-provider-password',
    );
    check(first.isSuccess, 'provider-first-open-${first.outcome.name}');
    check(
      sha256.convert(await File(first.value!.path).readAsBytes()).toString() ==
          result.plaintextHash,
      'provider-open-hash',
    );
    final second = await cache.prepare(
      reference,
      attachment,
      1,
      password: 'synthetic-provider-password',
    );
    check(
      second.isSuccess &&
          second.value!.path == first.value!.path &&
          cache.transformCount == 1,
      'provider-cached-reopen',
    );
    await cache.invalidateNote(reference);
    check(
      !await File(first.value!.path).exists(),
      'provider-lock-removes-plaintext',
    );
    // Picked inputs use the same registered descriptor acquisition as opens.
    final source = await files.attachmentSource(
      reference,
      attachmentId,
      verifyContent: true,
    );
    final rekey = await StreamingFileCipher.transform(
      source: source,
      destination: '${output.path}/provider-rekey.med',
      decryptSource: true,
      encryptDestination: true,
      sourcePassword: 'synthetic-provider-password',
      destinationPassword: 'synthetic-new-password',
    );
    check(rekey.plaintextHash == result.plaintextHash, 'provider-rekey-hash');
    await files.releaseAttachmentSources(reference);
    var rejected = false;
    try {
      await StreamingFileCipher.transform(
        source: source,
        destination: '${output.path}/released-lease.pending',
        decryptSource: true,
        encryptDestination: false,
        sourcePassword: 'synthetic-provider-password',
        verifyOutput: false,
      );
    } catch (_) {
      rejected = true;
    }
    check(
      rejected && !await File('${output.path}/released-lease.pending').exists(),
      'released-provider-source-rejected',
    );
    await plain.delete();
    await encrypted.delete();
    await File('${output.path}/provider-rekey.med').delete();
  } finally {
    await cache?.close();
    await cacheRoot?.delete(recursive: true);
    await files.close();
    for (final doc in created.reversed) {
      await documents.delete(location, doc);
    }
  }
}
