// Explicit synthetic device probe. Never imported by the normal app.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_file_actions.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/core/storage/owned_stream_writer.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

class _ScopedDocuments extends MobileLibraryDocuments {
  _ScopedDocuments(this.scope) : super(kind: LibraryLocationKind.androidTree);
  final LibraryDocument scope;
  bool blockPayloadReads = false;
  bool allowPayloadSources = false;
  int blockedReadAttempts = 0;
  final transferClocks = <String, Stopwatch>{};
  final transferBytes = <String, int>{};
  int largestTransferBytes = 0;
  int largestTransferMicros = 0;
  @override
  Future<void> append(
    LibraryLocation library,
    LibraryDocument document,
    Uint8List bytes, {
    required int offset,
  }) async {
    transferClocks.putIfAbsent(document.token, () => Stopwatch()..start());
    await super.append(library, document, bytes, offset: offset);
    transferBytes[document.token] = offset + bytes.length;
  }

  @override
  Future<void> flush(LibraryLocation library, LibraryDocument document) async {
    await super.flush(library, document);
    final clock = transferClocks.remove(document.token);
    final count = transferBytes.remove(document.token) ?? 0;
    if (clock != null && count > largestTransferBytes) {
      largestTransferBytes = count;
      largestTransferMicros = clock.elapsedMicroseconds;
    }
  }

  void _guard(LibraryDocument document) {
    if (blockPayloadReads && document.name.endsWith('.med')) {
      blockedReadAttempts++;
      throw StateError('payload-read-before-choice');
    }
  }

  @override
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  }) {
    _guard(document);
    return super.read(library, document, offset: offset, length: length);
  }

  @override
  Future<NativeDocumentSource> openSource(
    LibraryLocation library,
    LibraryDocument document,
  ) {
    if (!allowPayloadSources) _guard(document);
    return super.openSource(library, document);
  }

  @override
  Future<LibraryDocument> root(LibraryLocation library) async => scope;
}

void _check(bool condition, String code) {
  if (!condition) throw StateError(code);
}

Future<void> _speedProbe(Directory run, Map<String, Object?> report) async {
  final owner = const Uuid().v4();
  AndroidNativeCipher.initialize(
    ServicesBinding.rootIsolateToken,
    owner: owner,
  );
  try {
    final writer = await OwnedStreamWriter.open('${run.path}/checksum-vector');
    _check(writer.nativeChecksums, 'native-checksum-required');
    await writer.add(utf8.encode('123456789'), trackCrc: true);
    _check(writer.crc == 0xcbf43926, 'native-crc-vector');
    await writer.resetCrc();
    await writer.add(utf8.encode('123456789'), trackCrc: true);
    _check(writer.crc == 0xcbf43926, 'native-crc-reset');
    final receipt = await writer.close();
    _check(
      receipt.sha256Hex ==
          crypto.sha256.convert(utf8.encode('123456789123456789')).toString(),
      'native-sha-vector',
    );
    report['nativeChecksumVectorsPassed'] = true;
    final data = Uint8List.fromList(
      List.generate(2 * 1024 * 1024 + 17, (i) => i % 251),
    );
    final plain = await File('${run.path}/speed-plain').writeAsBytes(data);
    final hash = crypto.sha256.convert(data).toString();
    final timings = <String, int>{};
    String? writerHash;
    for (final native in [false, true]) {
      AndroidNativeCipher.initialize(
        ServicesBinding.rootIsolateToken,
        owner: owner,
        enableNative: native,
      );
      final watch = Stopwatch()..start();
      final output = await OwnedStreamWriter.open('${run.path}/writer-$native');
      _check(output.nativeChecksums == native, 'writer-backend-selection');
      for (var i = 0; i < 8; i++) {
        await output.add(data);
      }
      final receipt = await output.close();
      timings['writer-sha-${native ? 'native' : 'dart'}'] =
          watch.elapsedMicroseconds;
      _check(
        writerHash == null || writerHash == receipt.sha256Hex,
        'writer-hash-compatibility',
      );
      writerHash = receipt.sha256Hex;
    }
    report['writerFixtureBytes'] = data.length * 8;
    var source = StreamingFileSource(plain.path, data.length);
    for (final operation in ['encrypt', 'decrypt', 'rekey']) {
      final destination = '${run.path}/speed-$operation';
      final watch = Stopwatch()..start();
      final result = await StreamingFileCipher.transform(
        source: source,
        destination: destination,
        decryptSource: operation != 'encrypt',
        encryptDestination: operation != 'decrypt',
        sourcePassword: 'initial',
        destinationPassword: operation == 'rekey' ? 'final' : 'initial',
        expectedPlaintextBytes: data.length,
        verifyOutput: false,
        ownedTarget: OwnedWriteTarget.forPath(destination),
      );
      timings[operation] = watch.elapsedMicroseconds;
      _check(result.plaintextHash == hash, 'transform-plaintext-compatibility');
      if (operation == 'encrypt')
        source = StreamingFileSource(destination, result.length);
      if (operation == 'decrypt') {
        // Re-encrypt the original ciphertext with the same source credential.
        source = StreamingFileSource(
          '${run.path}/speed-encrypt',
          await File('${run.path}/speed-encrypt').length(),
        );
      }
    }
    final encrypted = await File('${run.path}/speed-encrypt').readAsBytes();
    final metadata = <String, dynamic>{
      'id': const Uuid().v4(),
      'title': 'Synthetic speed fixture',
      'content': 'Synthetic body\n',
      'timestamp': 1700000000000,
      'isLocked': false,
      'attachments': [
        {'id': 'payload', 'fileName': 'synthetic.bin', 'size': data.length},
      ],
    };
    for (final format in [ExportFormat.binary, ExportFormat.zip]) {
      for (final password in <String?>[null, 'archive-password']) {
        for (final native in [false, true]) {
          final label =
              '${format.name}-${password == null ? 'plain' : 'protected'}-${native ? 'native' : 'dart'}';
          final path = '${run.path}/$label.package';
          final watch = Stopwatch()..start();
          final output = await StreamingPackService(useNative: native)
              .exportPackage(
                metadata: metadata,
                attachments: {
                  'payload': StreamingFileSource(
                    '${run.path}/speed-encrypt',
                    encrypted.length,
                  ),
                },
                format: format,
                destination: path,
                operationDirectory: run.path,
                password: password,
              );
          timings['export-$label'] = watch.elapsedMicroseconds;
          _check(output.readbackBytes == 0, 'unexpected-export-readback');
          _check(
            output.sha256Hex ==
                crypto.sha256
                    .convert(await File(path).readAsBytes())
                    .toString(),
            'export-receipt-sha',
          );
          final directory = await Directory(
            '${run.path}/import-$label',
          ).create();
          watch.reset();
          final imported = await StreamingPackService(useNative: !native)
              .importPackage(
                source: path,
                operationDirectory: directory.path,
                password: password,
              );
          timings['import-$label'] = watch.elapsedMicroseconds;
          _check(
            imported.note.metadata['id'] == metadata['id'],
            'package-metadata-compatibility',
          );
          final payload = imported.attachments['payload']!;
          _check(
            crypto.sha256
                    .convert(await File(payload.path).readAsBytes())
                    .toString() ==
                crypto.sha256.convert(encrypted).toString(),
            'package-payload-compatibility',
          );
        }
      }
    }
    report['speedFixtureBytes'] = data.length;
    report['speedMicros'] = timings;
    report['crossBackendPackagesPassed'] = true;
  } finally {
    await AndroidNativeCipher.releaseOwner(owner);
    AndroidNativeCipher.initialize(ServicesBinding.rootIsolateToken);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Synthetic import check'))),
    ),
  );
  final report = <String, Object?>{'passed': false, 'stage': 0};
  const base = MobileLibraryDocuments(kind: LibraryLocationKind.androidTree);
  LibraryLocation? location;
  LibraryDocument? scope;
  Directory? run;
  ContentViewModel? editor;
  ProviderNoteFiles? files;
  SettingsService? settings;
  final scopeName = '.future-notes-validation-import-${const Uuid().v4()}';
  try {
    report['stage'] = 1;
    AndroidNativeCipher.initialize(ServicesBinding.rootIsolateToken);
    final selection = await MobileFileActions.channel.invokeMethod<String>(
      'readLibrarySelection',
    );
    _check(selection != null, 'selection-required');
    location = LibraryLocation.fromJson(
      Map<String, Object?>.from(
        (jsonDecode(selection!) as Map)['location'] as Map,
      ),
    );
    run = await (await getTemporaryDirectory()).createTemp(
      'future-notes-validation-import-',
    );
    run = Directory(await run.resolveSymbolicLinks());
    await _speedProbe(run, report);
    scope = await base.create(
      location,
      await base.root(location),
      scopeName,
      directory: true,
    );
    _check(scope.name == scopeName, 'scope-name-changed');
    final docs = _ScopedDocuments(scope);
    files = ProviderNoteFiles(
      documents: docs,
      location: location,
      libraryId: const Uuid().v4(),
      privateRoot: run.path,
    );
    settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: '${run.path}/library',
        settingsFile: '${run.path}/configuration/settings.json',
      ),
    );
    await settings.init();
    final cipher = EncryptionService();
    editor = ContentViewModel(
      fileService: files,
      encryptionService: cipher,
      settings: settings,
      startBackgroundServices: false,
    );
    final id = const Uuid().v4();
    const plaintextLength = 8 * 1024 * 1024 + 17;
    final plaintext = Uint8List.fromList(
      List.generate(plaintextLength, (i) => i % 251),
    );
    final bytes = await cipher.encryptBinary(plaintext);
    final input = await File('${run.path}/synthetic.med').writeAsBytes(bytes);
    final metadata = <String, dynamic>{
      'id': id,
      'title': 'Synthetic import probe',
      'content': 'Synthetic body\n',
      'timestamp': 1700000000000,
      'isLocked': false,
      'attachments': [
        {'id': 'payload', 'fileName': 'synthetic.bin', 'size': plaintextLength},
        {'id': 'second', 'fileName': 'second.bin', 'size': plaintextLength},
      ],
    };
    report['stage'] = 2;
    final package = '${run.path}/synthetic.fnote';
    await StreamingPackService().exportPackage(
      metadata: metadata,
      attachments: {
        'payload': StreamingFileSource(input.path, bytes.length),
        'second': StreamingFileSource(input.path, bytes.length),
      },
      format: ExportFormat.binary,
      destination: package,
      operationDirectory: run.path,
    );
    report['stage'] = 3;
    var savingProgressObserved = false;
    var finishingObserved = false;
    var progressValid = true;
    final previous = <String, int>{};
    final savingClocks = <String, Stopwatch>{};
    var savingBatchMicros = 0;
    final observed = <Object>{};
    void observe() {
      for (final job in editor!.attachmentJobsNotifier.value) {
        if (!observed.add(job)) continue;
        job.progress.addListener(() {
          final event = job.progress.value;
          final file = event.fileProgress;
          if (file == null) return;
          if (file.total == 0) {
            finishingObserved = true;
            return;
          }
          progressValid =
              progressValid &&
              file.fileCount == 2 &&
              file.overallTotal == bytes.length * 2 &&
              file.overallBytes >= (previous[event.id] ?? 0) &&
              (file.fileName == 'synthetic.bin' ||
                  file.fileName == 'second.bin');
          savingClocks.putIfAbsent(event.id, () => Stopwatch()..start());
          if (savingBatchMicros == 0 &&
              file.overallBytes == file.overallTotal) {
            savingBatchMicros = savingClocks[event.id]!.elapsedMicroseconds;
          }
          previous[event.id] = file.overallBytes;
          savingProgressObserved = true;
        });
      }
    }

    editor.attachmentJobsNotifier.addListener(observe);
    final created = await editor.importNoteFile(package);
    report['firstImportSucceeded'] = created.isSuccess;
    _check(created.isSuccess, 'first-import-failed');
    final importedRef = (await files.resolveNote(created.value!.fileName))!;
    final decoded = await cipher.decryptAppResult(
      (await files.readResolved(importedRef))!,
    );
    _check(decoded.isSuccess, 'synthetic-metadata-unreadable');
    final stored = jsonDecode(decoded.value!) as Map;
    final storageId =
        ((stored['attachments'] as List).first as Map)['id'] as String;
    final retained = await files.attachmentSource(
      importedRef,
      storageId,
      verifyContent: false,
    );
    final opened = await StreamingFileCipher.transform(
      source: retained,
      destination: '${run.path}/check.raw',
      decryptSource: true,
      encryptDestination: false,
      verifyOutput: false,
      expectedPlaintextBytes: plaintextLength,
      requireWholeSource: true,
    );
    _check(
      opened.plaintextHash == crypto.sha256.convert(plaintext).toString(),
      'native-copy-changed-ciphertext',
    );
    report['nativeCopyDecryptionPassed'] = true;
    await files.releaseAttachmentSources(importedRef);
    report['stage'] = 5;
    var count = 0;
    for (final decision in [
      NoteImportDecision.ignore,
      NoteImportDecision.duplicate,
      NoteImportDecision.replace,
    ]) {
      docs.blockPayloadReads = true;
      final result = await editor.importNoteFile(
        package,
        resolveConflict: (match) async {
          _check(match.identical == null, 'unexpected-content-comparison');
          _check(docs.blockedReadAttempts == 0, 'payload-read-before-choice');
          count++;
          if (decision == NoteImportDecision.replace) {
            // Metadata/descriptor availability is allowed after the choice;
            // payload reads remain forbidden through replacement completion.
            docs.allowPayloadSources = true;
          }
          return decision;
        },
      );
      _check(result.isSuccess, 'decision-${decision.name}-failed');
      final expected = switch (decision) {
        NoteImportDecision.ignore => NoteImportDisposition.ignored,
        NoteImportDecision.duplicate => NoteImportDisposition.duplicated,
        NoteImportDecision.replace => NoteImportDisposition.replaced,
      };
      _check(result.value!.disposition == expected, 'wrong-disposition');
    }
    report['decisionCount'] = count;
    report['payloadReadsBeforeChoice'] = docs.blockedReadAttempts;
    report['existingPayloadReadAttempts'] = docs.blockedReadAttempts;
    report['savingProgressObserved'] = savingProgressObserved;
    report['finishingObserved'] = finishingObserved;
    report['progressValid'] = progressValid;
    report['largestTransferBytes'] = docs.largestTransferBytes;
    report['largestTransferMicros'] = docs.largestTransferMicros;
    report['savingBatchBytes'] = bytes.length * 2;
    report['savingBatchMicros'] = savingBatchMicros;
    report['noPayloadChunkWrites'] = docs.largestTransferBytes < 1024 * 1024;
    report['passed'] =
        count == 3 &&
        savingProgressObserved &&
        finishingObserved &&
        progressValid &&
        docs.largestTransferBytes < 1024 * 1024 &&
        savingBatchMicros > 0;
  } catch (error) {
    report['failureType'] = error.runtimeType.toString();
    // Only the probe's fixed labels are allowed in its content-free summary.
    if (error is StateError && RegExp(r'^[a-z-]+$').hasMatch(error.message)) {
      report['failureCode'] = error.message;
    }
  } finally {
    try {
      editor?.dispose();
      await editor?.closeLibraryResources();
      await files?.close();
      await settings?.closePersistence();
      if (scope != null && location != null && scope.name == scopeName) {
        Future<void> remove(LibraryDocument doc) async {
          if (doc.isDirectory) {
            for (final child in await base.children(location!, doc)) {
              await remove(child);
            }
          }
          await base.delete(location!, doc);
        }

        await remove(scope);
        report['providerCleanupPassed'] = true;
      }
      if (run != null) {
        _check(
          run.path.startsWith(
                '${await (await getTemporaryDirectory()).resolveSymbolicLinks()}/',
              ) &&
              run.path
                  .split('/')
                  .last
                  .startsWith('future-notes-validation-import-'),
          'invalid-private-cleanup',
        );
        await run.delete(recursive: true);
      }
    } catch (_) {
      report['cleanupFailed'] = true;
    }
  }
  // Android's Flutter log sink truncates long individual messages.
  final speed = report.remove('speedMicros');
  if (speed != null) print('FN_SPEED_PROBE ${jsonEncode(speed)}');
  print('FN_IMPORT_PROBE ${jsonEncode(report)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            report['passed'] == true
                ? 'Synthetic import check passed'
                : 'Synthetic import check failed',
          ),
        ),
      ),
    ),
  );
}
