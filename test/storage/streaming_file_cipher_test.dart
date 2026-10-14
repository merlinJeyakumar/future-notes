import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_transform_worker.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
  });
  tearDown(() => deleteValidationRun(run));
  String path(String name) => p.join(run.path, name);
  Uint8List key(String? password) {
    if (password == null) {
      return Uint8List.fromList(
        utf8.encode('MySuperSecretAppKeyForJsonStore!'),
      );
    }
    final bytes = utf8.encode(password);
    return Uint8List(32)..setRange(0, bytes.length.clamp(0, 32), bytes);
  }

  Uint8List encrypt(Uint8List bytes, String? password) {
    final iv = legacy.IV(Uint8List.fromList(List.generate(16, (i) => i)));
    final encrypted = legacy.Encrypter(
      legacy.AES(legacy.Key(key(password))),
    ).encryptBytes(bytes, iv: iv).bytes;
    return Uint8List(16 + encrypted.length)
      ..setAll(0, iv.bytes)
      ..setAll(16, encrypted);
  }

  Uint8List decrypt(Uint8List bytes, String? password) => Uint8List.fromList(
    legacy.Encrypter(legacy.AES(legacy.Key(key(password)))).decryptBytes(
      legacy.Encrypted(bytes.sublist(16)),
      iv: legacy.IV(bytes.sublist(0, 16)),
    ),
  );

  for (final length in [0, 1, 15, 16, 17, 1024 * 1024 - 1, 1024 * 1024 + 17]) {
    test('legacy reader accepts streaming output of $length bytes', () async {
      final bytes = Uint8List.fromList(List.generate(length, (i) => i % 251));
      await File(path('source')).writeAsBytes(bytes);
      final result = await StreamingFileCipher.transform(
        source: StreamingFileSource(path('source'), length),
        destination: path('cipher'),
        decryptSource: false,
        encryptDestination: true,
        destinationPassword: 'synthetic-password',
      );
      expect(result.plaintextHash, sha256.convert(bytes).toString());
      expect(
        decrypt(await File(path('cipher')).readAsBytes(), 'synthetic-password'),
        bytes,
      );
    });
  }
  test(
    'streaming reads old ciphertext and rekeys without plaintext staging',
    () async {
      final bytes = Uint8List.fromList(
        List.generate(1024 * 1024 + 7, (i) => i % 239),
      );
      final ciphertext = encrypt(bytes, 'old-synthetic');
      await File(path('source')).writeAsBytes(ciphertext);
      await StreamingFileCipher.transform(
        source: StreamingFileSource(path('source'), ciphertext.length),
        destination: path('rekeyed'),
        decryptSource: true,
        encryptDestination: true,
        sourcePassword: 'old-synthetic',
        destinationPassword: 'new-synthetic',
      );
      expect(
        decrypt(await File(path('rekeyed')).readAsBytes(), 'new-synthetic'),
        bytes,
      );
      expect((await run.list().toList()).length, 2);
    },
  );
  test('empty old ciphertext decrypts successfully', () async {
    // The old buffered encrypt package throws on zero-length input. Construct
    // the legitimate legacy PKCS7 empty block independently of our new writer.
    final iv = legacy.IV(Uint8List(16));
    final padded = legacy.Encrypter(
      legacy.AES(legacy.Key(key(null)), padding: null),
    ).encryptBytes(List.filled(16, 16), iv: iv).bytes;
    final bytes = Uint8List(32)
      ..setAll(0, iv.bytes)
      ..setAll(16, padded);
    await File(path('source')).writeAsBytes(bytes);
    final result = await StreamingFileCipher.transform(
      source: StreamingFileSource(path('source'), bytes.length),
      destination: path('export'),
      decryptSource: true,
      encryptDestination: false,
    );
    expect(result.length, 0);
    expect(await File(path('export')).length(), 0);
  });
  test('validated file slice excludes surrounding package bytes', () async {
    await File(path('source')).writeAsBytes([9, 9, 1, 2, 3, 8, 8]);
    await StreamingFileCipher.transform(
      source: StreamingFileSource(path('source'), 3, offset: 2),
      destination: path('cipher'),
      decryptSource: false,
      encryptDestination: true,
    );
    expect(decrypt(await File(path('cipher')).readAsBytes(), null), [1, 2, 3]);
  });
  test('wrong key removes only its failed staged output', () async {
    final bytes = encrypt(Uint8List.fromList([1, 2, 3]), 'right-synthetic');
    await File(path('source')).writeAsBytes(bytes);
    await expectLater(
      StreamingFileCipher.transform(
        source: StreamingFileSource(path('source'), bytes.length),
        destination: path('failed'),
        decryptSource: true,
        encryptDestination: true,
        sourcePassword: 'wrong-synthetic',
      ),
      throwsFormatException,
    );
    expect(await File(path('failed')).exists(), isFalse);
    expect(await File(path('source')).readAsBytes(), bytes);
  });
  test(
    'verification reports bounded real byte counts and immediate terminal phase',
    () async {
      const length = 4 * 1024 * 1024;
      await File(path('source')).writeAsBytes(Uint8List(length));
      final verification = <int>[];
      await StreamingFileCipher.transform(
        source: StreamingFileSource(path('source'), length),
        destination: path('verified'),
        decryptSource: false,
        encryptDestination: true,
        progress: (phase, bytes, total) {
          expect(total, length);
          if (phase == 'Verifying') verification.add(bytes);
        },
      );
      expect(verification.first, 0);
      expect(verification.last, length);
      expect(
        verification.every((bytes) => bytes >= 0 && bytes <= length),
        isTrue,
      );
    },
  );

  test('existing destination remains untouched', () async {
    await File(path('source')).writeAsBytes([1]);
    await File(path('destination')).writeAsBytes([7]);
    await expectLater(
      StreamingFileCipher.transform(
        source: StreamingFileSource(path('source'), 1),
        destination: path('destination'),
        decryptSource: false,
        encryptDestination: true,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(path('destination')).readAsBytes(), [7]);
  });
  test('cancellation closes handles and removes candidate', () async {
    await File(path('source')).writeAsBytes(Uint8List(2 * 1024 * 1024));
    var cancel = false;
    await expectLater(
      StreamingFileCipher.transform(
        source: StreamingFileSource(path('source'), 2 * 1024 * 1024),
        destination: path('cancelled'),
        decryptSource: false,
        encryptDestination: true,
        cancelled: () => cancel,
        progress: (phase, bytes, _) {
          if (bytes > 0) cancel = true;
        },
      ),
      throwsA(isA<FileJobCancelled>()),
    );
    expect(await File(path('cancelled')).exists(), isFalse);
  });
  test(
    'source length and alignment errors reject before creating output',
    () async {
      await File(path('source')).writeAsBytes([1, 2]);
      for (final length in [3, -1]) {
        await expectLater(
          StreamingFileCipher.transform(
            source: StreamingFileSource(path('source'), length),
            destination: path('rejected'),
            decryptSource: false,
            encryptDestination: true,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        StreamingFileCipher.transform(
          source: StreamingFileSource(path('source'), 2),
          destination: path('rejected'),
          decryptSource: true,
          encryptDestination: true,
        ),
        throwsFormatException,
      );
      expect(await File(path('rejected')).exists(), isFalse);
    },
  );
  test(
    'fast worker results precede exit and graceful close joins every descriptor',
    () async {
      await File(path('empty')).writeAsBytes([]);
      final worker = AttachmentTransformWorker();
      final jobs = List.generate(
        12,
        (index) => worker.submit(
          FileTransformRequest(
            source: StreamingFileSource(path('empty'), 0),
            destination: path('empty-$index'),
            decryptSource: false,
            encryptDestination: true,
          ),
        ),
      );
      final closing = worker.close();
      for (final job in jobs) {
        final result = await job.result;
        expect(result.isSuccess, isTrue, reason: result.message);
        expect(result.value!.length, 32);
      }
      await closing;
      await File(path('empty')).delete();
    },
  );

  test(
    'owned worker settles results and acknowledges queued cancellation',
    () async {
      await File(path('source')).writeAsBytes(Uint8List(1024 * 1024));
      final worker = AttachmentTransformWorker();
      final first = worker.submit(
        FileTransformRequest(
          source: StreamingFileSource(path('source'), 1024 * 1024),
          destination: path('first'),
          decryptSource: false,
          encryptDestination: true,
        ),
      );
      final second = worker.submit(
        FileTransformRequest(
          source: StreamingFileSource(path('source'), 1024 * 1024),
          destination: path('second'),
          decryptSource: false,
          encryptDestination: true,
        ),
      );
      final cancelled = second.cancel();
      expect((await first.result).isSuccess, isTrue);
      expect((await cancelled).outcome, OperationOutcome.cancelled);
      await worker.close();
      expect(await File(path('second')).exists(), isFalse);
    },
  );
}
