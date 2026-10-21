import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late String library;
  late NativeStoragePrimitives storage;
  setUp(() async {
    run = await createValidationRun();
    library = p.join(run.path, 'library');
    storage = NativeStoragePrimitives(
      StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: library,
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
    );
    await Directory(library).create();
  });
  tearDown(() => deleteValidationRun(run));

  test(
    'revision distinguishes missing, empty and present targets without writes',
    () async {
      final file = File(p.join(library, 'synthetic.enc'));
      final missing = await storage.captureRevision(file.path);
      expect(missing.exists, isFalse);
      expect(await file.exists(), isFalse);
      await file.writeAsBytes([], flush: true);
      final empty = await storage.captureRevision(file.path);
      expect(empty.exists, isTrue);
      expect(empty.length, 0);
      expect(
        empty.sha256Hex,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      await file.writeAsString('abc', flush: true);
      final present = await storage.captureRevision(file.path);
      expect(present.length, 3);
      expect(
        present.sha256Hex,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(present.matches(empty), isFalse);
      expect(await file.readAsString(), 'abc');
    },
  );

  test(
    'same-length changes invalidate revisions even with restored modification time',
    () async {
      final file = File(p.join(library, 'synthetic.enc'));
      await file.writeAsString('abc', flush: true);
      final before = await file.stat();
      final revision = await storage.captureRevision(file.path);
      expect(
        revision.matches(await storage.captureRevision(file.path)),
        isTrue,
      );
      await file.writeAsString('abd', flush: true);
      await file.setLastModified(before.modified);
      expect(
        revision.matches(await storage.captureRevision(file.path)),
        isFalse,
      );
    },
  );

  test(
    'revision reads use bounded windows and detect mid-read source changes',
    () async {
      final file = File(p.join(library, 'synthetic.enc'));
      final handle = await file.open(mode: FileMode.write);
      try {
        for (var i = 0; i < 3; i++) {
          await handle.writeFrom(Uint8List(NativeStoragePrimitives.ioWindow));
        }
        await handle.flush();
      } finally {
        await handle.close();
      }
      final chunks = <int>[];
      final revision = await storage.captureRevision(
        file.path,
        onChunk: (n) async {
          chunks.add(n);
        },
      );
      expect(revision.length, 3 * NativeStoragePrimitives.ioWindow);
      expect(chunks.last, revision.length);
      var previous = 0;
      for (final processed in chunks) {
        expect(
          processed - previous,
          inInclusiveRange(1, NativeStoragePrimitives.ioWindow),
        );
        previous = processed;
      }
      await expectLater(
        storage.captureRevision(
          file.path,
          onChunk: (n) async {
            if (n == NativeStoragePrimitives.ioWindow) {
              await file.writeAsBytes([7], mode: FileMode.append, flush: true);
            }
          },
        ),
        throwsStateError,
      );
    },
  );

  test(
    'revision and lease reject escaped paths before creating storage',
    () async {
      final outside = p.join(p.dirname(run.path), 'synthetic-forbidden.enc');
      await expectLater(storage.captureRevision(outside), throwsArgumentError);
      await expectLater(storage.acquireLease(outside), throwsArgumentError);
      expect(await File(outside).exists(), isFalse);
      await expectLater(storage.captureRevision(library), throwsStateError);
    },
  );

  test(
    'lease rejects note filenames and retains lock object after release',
    () async {
      final note = p.join(library, 'synthetic.enc');
      final rejected = await storage.acquireLease(note);
      expect(rejected.outcome, OperationOutcome.rejectedInput);
      expect(await File(note).exists(), isFalse);
      final path = p.join(library, '.future-notes-library.lock');
      final acquired = await storage.acquireLease(path);
      expect(acquired.isSuccess, isTrue);
      try {
        expect(await File(path).exists(), isTrue);
      } finally {
        await acquired.value!.close();
      }
      expect(await File(path).exists(), isTrue);
    },
  );

  test(
    'concurrent coordinator leases reject a second owner and permit reacquisition',
    () async {
      final path = p.join(library, '.future-notes-library.lock');
      final acquired = await storage.acquireLease(path);
      expect(acquired.isSuccess, isTrue);
      try {
        final other = NativeStoragePrimitives(storage.environment);
        expect(
          (await other.acquireLease(path)).outcome,
          OperationOutcome.conflict,
        );
      } finally {
        await acquired.value!.close();
      }
      await acquired.value!.close(); // Explicit repeated release is idempotent.
      final next = await storage.acquireLease(path);
      expect(next.isSuccess, isTrue);
      await next.value!.close();
    },
  );

  test('settings and library leases have independent ownership', () async {
    final libraryLease = await storage.acquireLease(
      p.join(library, '.future-notes-library.lock'),
    );
    final settingsLease = await storage.acquireLease(
      p.join(run.path, 'configuration', '.future-notes-settings.lock'),
    );
    try {
      expect(libraryLease.isSuccess, isTrue);
      expect(settingsLease.isSuccess, isTrue);
    } finally {
      await settingsLease.value?.close();
      await libraryLease.value?.close();
    }
  });

  test(
    'Windows native handle contention rejects without waiting for unlock',
    () async {
      final path = p.join(library, '.future-notes-library.lock');
      final externalHandle = await File(path).open(mode: FileMode.append);
      await externalHandle.lock(FileLock.exclusive);
      try {
        final result = await storage
            .acquireLease(path)
            .timeout(const Duration(seconds: 5));
        expect(result.outcome, OperationOutcome.conflict);
        expect(result.value, isNull);
      } finally {
        await externalHandle.unlock();
        await externalHandle.close();
      }
      final acquired = await storage.acquireLease(path);
      expect(acquired.isSuccess, isTrue);
      await acquired.value!.close();
    },
    skip: !Platform.isWindows,
  );
}
