import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late Directory root;
  late NoteReference note;
  late StreamingFileSource source;
  final caches = <AttachmentOpenCache>[];
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    root = await Directory(p.join(run.path, 'cache')).create();
    final binding = StorageBinding(p.join(run.path, 'library'), 0);
    note = NoteReference(
      binding: binding,
      fileName: 'note_synthetic',
      format: NoteStorageFormat.folder,
      contentPath: binding.child('note_synthetic/content.enc'),
      attachmentLocation: binding.child('note_synthetic/attachments'),
    );
    final plain = File(p.join(run.path, 'synthetic-input'));
    await plain.writeAsString('synthetic bytes');
    final cipher = p.join(run.path, 'synthetic.med');
    final result = await StreamingFileCipher.transform(
      source: StreamingFileSource(plain.path, await plain.length()),
      destination: cipher,
      decryptSource: false,
      encryptDestination: true,
    );
    source = StreamingFileSource(cipher, result.length);
  });
  tearDown(() async {
    for (final cache in caches) {
      await cache.close();
    }
    caches.clear();
    await deleteValidationRun(run);
  });
  AttachmentOpenCache create({
    AttachmentSourceResolver? resolver,
    AttachmentSourcePreparer? preparer,
    AttachmentPerformance Function()? performance,
    CacheFileRemover? remover,
  }) {
    final cache = AttachmentOpenCache(
      rootResolver: () async => root.path,
      sourceResolver: resolver ?? (_, id) async => source,
      sourcePreparer: preparer,
      performance: performance,
      removeFile: remover,
    );
    caches.add(cache);
    return cache;
  }

  AttachmentModel attachment([String id = 'synthetic']) =>
      AttachmentModel(id: id, fileName: 'sample.txt', size: 15);

  for (final check in [false, true]) {
    for (final verify in [false, true]) {
      test(
        'open scan settings check=$check verify=$verify preserve exact bytes and cache reuse',
        () async {
          var profile = AttachmentPerformance.defaults.copyWith(
            checkBeforeOpen: check,
            verifyAfterOpen: verify,
          );
          var checked = 0;
          final cache = create(
            performance: () => profile,
            preparer:
                (
                  _,
                  _, {
                  onProgress,
                  cancellation,
                  required verifyContent,
                }) async {
                  if (!verifyContent) return source;
                  checked++;
                  final hash = sha256
                      .convert(await File(source.path).readAsBytes())
                      .toString();
                  onProgress?.call(
                    'Checking attachment',
                    source.length,
                    source.length,
                  );
                  return StreamingFileSource(
                    source.path,
                    source.length,
                    sha256Hex: hash,
                  );
                },
          );
          final phases = <String>[];
          final result = await cache.prepare(
            note,
            attachment(),
            0,
            onProgress: (phase, _, _) => phases.add(phase),
          );
          expect(result.isSuccess, isTrue, reason: result.message);
          expect(
            await File(result.value!.path).readAsString(),
            'synthetic bytes',
          );
          expect(checked, check ? 1 : 0);
          expect(phases.contains('Verifying'), verify);
          expect(phases.contains('Checking attachment'), check);
          expect(phases.contains('Preparing'), check);
          expect(
            (await cache.prepare(note, attachment(), 0)).value!.path,
            result.value!.path,
          );
          expect(cache.transformCount, 1);
          if (!check || !verify) {
            profile = profile.copyWith(
              checkBeforeOpen: true,
              verifyAfterOpen: true,
            );
            expect(
              (await cache.prepare(note, attachment(), 0)).isSuccess,
              isTrue,
            );
            expect(cache.transformCount, 2);
          }
        },
      );
    }
  }

  test(
    'cancelling a source check joins its reader and never starts decryption',
    () async {
      final started = Completer<void>();
      final readerClosed = Completer<void>();
      final cache = create(
        preparer:
            (_, _, {onProgress, cancellation, required verifyContent}) async {
              final cancelled = Completer<void>();
              final detach = cancellation!.listen(() {
                if (!cancelled.isCompleted) cancelled.complete();
              });
              onProgress?.call('Checking attachment', 1, source.length);
              started.complete();
              await cancelled.future;
              detach();
              readerClosed.complete();
              throw StateError('synthetic cancelled reader');
            },
      );
      final opening = cache.prepare(note, attachment(), 0);
      await started.future;
      await cache.cancel(note, 'synthetic', 0);
      expect(readerClosed.isCompleted, isTrue);
      expect((await opening).outcome, OperationOutcome.cancelled);
      expect(cache.transformCount, 0);
      expect(cache.peek(note, 'synthetic', 0), isNull);
    },
  );

  test(
    'explicit open produces a file and repeated/concurrent opens decrypt once',
    () async {
      var reads = 0;
      final cache = create(
        resolver: (_, id) async {
          reads++;
          return source;
        },
      );
      expect(cache.peek(note, 'synthetic', 0), isNull);
      final a = cache.prepare(note, attachment(), 0);
      final b = cache.prepare(note, attachment(), 0);
      final results = await Future.wait([a, b]);
      expect(results.every((r) => r.isSuccess), isTrue);
      expect(results[0].value!.path, results[1].value!.path);
      expect(
        await File(results[0].value!.path).readAsString(),
        'synthetic bytes',
      );
      expect(
        (await cache.prepare(note, attachment(), 0)).value!.path,
        results[0].value!.path,
      );
      expect(reads, 1);
      expect(cache.transformCount, 1);
    },
  );
  test('credentials and note identities cannot share cache entries', () async {
    final cache = create();
    final first = (await cache.prepare(note, attachment(), 0)).value!;
    final credential = (await cache.prepare(note, attachment(), 1)).value!;
    final other = NoteReference(
      binding: note.binding,
      fileName: 'other',
      format: note.format,
      contentPath: note.binding.child('other/content.enc'),
      attachmentLocation: note.attachmentLocation,
    );
    final second = (await cache.prepare(other, attachment(), 0)).value!;
    expect({first.path, credential.path, second.path}.length, 3);
    await cache.invalidateNote(note);
    expect(cache.peek(note, 'synthetic', 0), isNull);
    expect(await File(first.path).exists(), isFalse);
    expect(await File(second.path).exists(), isTrue);
  });
  test(
    'missing or externally changed cache file triggers fresh preparation',
    () async {
      final cache = create();
      final first = (await cache.prepare(note, attachment(), 0)).value!;
      await File(first.path).delete();
      final second = (await cache.prepare(note, attachment(), 0)).value!;
      expect(second.path, isNot(first.path));
      await File(second.path).writeAsString('changed');
      expect(
        (await cache.prepare(note, attachment(), 0)).value!.path,
        isNot(second.path),
      );
      expect(cache.transformCount, 3);
    },
  );
  test('invalidation rejects late preparation publication', () async {
    final gate = Completer<StreamingFileSource>();
    final entered = Completer<void>();
    final cache = create(
      resolver: (_, id) {
        entered.complete();
        return gate.future;
      },
    );
    final opening = cache.prepare(note, attachment(), 0);
    await entered.future;
    final invalidating = cache.invalidateNote(note);
    gate.complete(source);
    expect((await opening).outcome, OperationOutcome.cancelled);
    await invalidating;
    expect(cache.peek(note, 'synthetic', 0), isNull);
    expect(cache.transformCount, 0);
  });
  test(
    'sharing failure revokes cache and next startup removes retained plaintext',
    () async {
      var held = true;
      final cache = create(
        remover: (file) async {
          if (held) {
            throw const FileSystemException('Synthetic sharing failure');
          }
          await file.delete();
        },
      );
      final file = (await cache.prepare(note, attachment(), 0)).value!;
      expect((await cache.invalidateNote(note)).deferred, 1);
      expect(cache.peek(note, 'synthetic', 0), isNull);
      expect(await File(file.path).exists(), isTrue);
      expect((await cache.close()).deferred, 1);
      caches.remove(cache);
      held = false;
      final next = create();
      await next.initialize();
      expect(await File(file.path).exists(), isFalse);
    },
  );
  test('startup retains a live other cache owner', () async {
    final live = create();
    final file = (await live.prepare(note, attachment(), 0)).value!;
    final next = create();
    await next.initialize();
    expect(await File(file.path).exists(), isTrue);
  });
  test('empty attachment is a successful cached file', () async {
    final input = await File(p.join(run.path, 'empty')).create();
    final destination = p.join(run.path, 'empty.med');
    final cipher = await StreamingFileCipher.transform(
      source: StreamingFileSource(input.path, 0),
      destination: destination,
      decryptSource: false,
      encryptDestination: true,
    );
    source = StreamingFileSource(destination, cipher.length);
    final cache = create();
    final result = await cache.prepare(
      note,
      AttachmentModel(id: 'empty', fileName: 'empty.txt', size: 0),
      0,
    );
    expect(result.isSuccess, isTrue);
    expect(result.value!.length, 0);
  });
  test(
    'files above old 8 MiB preview limit use bounded file preparation',
    () async {
      const size = 8 * 1024 * 1024 + 17;
      final input = File(p.join(run.path, 'large-video'));
      final handle = await input.open(mode: FileMode.writeOnly);
      await handle.truncate(size);
      await handle.close();
      final destination = p.join(run.path, 'video.med');
      final cipher = await StreamingFileCipher.transform(
        source: StreamingFileSource(input.path, size),
        destination: destination,
        decryptSource: false,
        encryptDestination: true,
      );
      source = StreamingFileSource(destination, cipher.length);
      final cache = create();
      final result = await cache.prepare(
        note,
        AttachmentModel(id: 'large', fileName: 'demo-video.mp4', size: size),
        0,
      );
      expect(result.isSuccess, isTrue);
      expect(await File(result.value!.path).length(), size);
      expect(
        (await cache.prepare(
          note,
          AttachmentModel(id: 'large', fileName: 'demo-video.mp4'),
          0,
        )).value!.path,
        result.value!.path,
      );
      expect(cache.transformCount, 1);
    },
  );
  test('failed ciphertext never creates a reusable plaintext entry', () async {
    await File(source.path).writeAsString('truncated');
    source = StreamingFileSource(source.path, 9);
    final cache = create();
    expect((await cache.prepare(note, attachment(), 0)).isSuccess, isFalse);
    expect(cache.peek(note, 'synthetic', 0), isNull);
    final files = await root
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.pending'))
        .toList();
    expect(files, isEmpty);
  });

  test(
    'cancellation joins the actual worker and removes partial plaintext',
    () async {
      const size = 9 * 1024 * 1024;
      final input = File(p.join(run.path, 'cancel-source'));
      final handle = await input.open(mode: FileMode.writeOnly);
      await handle.truncate(size);
      await handle.close();
      final cipherPath = p.join(run.path, 'cancel.med');
      final cipher = await StreamingFileCipher.transform(
        source: StreamingFileSource(input.path, size),
        destination: cipherPath,
        decryptSource: false,
        encryptDestination: true,
      );
      source = StreamingFileSource(cipherPath, cipher.length);
      final cache = create();
      Future<void>? cancelling;
      final result = await cache.prepare(
        note,
        attachment(),
        0,
        onProgress: (phase, bytes, total) {
          if (phase == 'Decrypting' && cancelling == null)
            cancelling = cache.cancel(note, 'synthetic', 0);
        },
      );
      await cancelling;
      expect(result.outcome, OperationOutcome.cancelled);
      expect(cache.peek(note, 'synthetic', 0), isNull);
      expect(
        await root
            .list(recursive: true)
            .where((e) => e.path.endsWith('.pending'))
            .toList(),
        isEmpty,
      );
    },
  );
  test('legacy mixed-key attachment fallback uses a fresh output', () async {
    final cache = create();
    final opened = await cache.prepare(
      note,
      attachment(),
      0,
      password: 'synthetic-note-password',
    );
    expect(opened.isSuccess, isTrue);
    expect(cache.transformCount, 2);
    expect(await File(opened.value!.path).readAsString(), 'synthetic bytes');
  });
  test(
    'corrupt cleanup receipt still removes only named cache files of a dead owner',
    () async {
      final cache = create(
        remover: (_) async =>
            throw const FileSystemException('Synthetic sharing failure'),
      );
      final opened = (await cache.prepare(note, attachment(), 0)).value!;
      await cache.close();
      caches.remove(cache);
      final folder = File(opened.path).parent;
      final unknown = await File(
        p.join(folder.path, 'unrelated.txt'),
      ).writeAsString('retain');
      await File(p.join(folder.path, 'cleanup.json')).writeAsString('{');
      final next = create();
      await next.initialize();
      expect(await File(opened.path).exists(), isFalse);
      expect(await unknown.exists(), isTrue);
    },
  );
}
