import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/decryption_result.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';

// Independent fixtures made through the installed legacy AES wrapper. Explicit
// padding also constructs legitimate zero-length payloads its writer cannot make.
final _fixtureKey = legacy.Key.fromUtf8('synthetic-key-123456789012345678');
final _appKey = legacy.Key.fromUtf8('MySuperSecretAppKeyForJsonStore!');
final _fixtureIv = legacy.IV(
  Uint8List.fromList(List.generate(16, (i) => i + 1)),
);

Uint8List _cipher(List<int> payload, legacy.Key key, legacy.IV iv) {
  final count = 16 - payload.length % 16;
  final padded = Uint8List.fromList([...payload, ...List.filled(count, count)]);
  return legacy.Encrypter(
    legacy.AES(key, padding: null),
  ).encryptBytes(padded, iv: iv).bytes;
}

Uint8List _binary(List<int> payload, legacy.Key key) => Uint8List.fromList([
  ..._fixtureIv.bytes,
  ..._cipher(payload, key, _fixtureIv),
]);

String _text(String body, legacy.Key key, {bool noIvPrefix = false}) {
  final iv = noIvPrefix ? legacy.IV(key.bytes.sublist(0, 16)) : _fixtureIv;
  final ciphertext = base64Encode(_cipher(utf8.encode(body), key, iv));
  return noIvPrefix ? ciphertext : '${iv.base64}:$ciphertext';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = EncryptionService();
  const password = 'synthetic-key-123456789012345678';
  test(
    'empty writers produce the existing full padding block accepted by legacy readers',
    () async {
      final body = await service.encrypt('', password: password);
      expect((await service.decryptResult(body, password: password)).value, '');
      final parts = body.split(':');
      expect(
        legacy.Encrypter(legacy.AES(_fixtureKey)).decrypt(
          legacy.Encrypted.fromBase64(parts.last),
          iv: legacy.IV.fromBase64(parts.first),
        ),
        '',
      );
      final binary = await service.encryptBinary(
        Uint8List(0),
        password: password,
      );
      expect(binary.length, 32);
      expect(
        (await service.decryptBinaryResult(binary, password: password)).value,
        isEmpty,
      );
      final app = await service.encryptApp('');
      expect((await service.decryptAppResult(app)).value, '');
      expect(
        app,
        base64Encode(
          _cipher([], _appKey, legacy.IV.fromUtf8('1234567890123456')),
        ),
      );
    },
  );

  test('empty string has success authority distinct from a failure', () async {
    final fixture = _text('', _fixtureKey);
    final result = await service.decryptResult(fixture, password: password);
    expect(result.isSuccess, isTrue);
    expect(result.value, '');
    expect(result.failure, isNull);
    expect(result.usedLegacyFallback, isFalse);
    expect(
      legacy.Encrypter(legacy.AES(_fixtureKey)).decrypt(
        legacy.Encrypted.fromBase64(fixture.split(':').last),
        iv: _fixtureIv,
      ),
      '',
    );
  });

  test(
    'plaintext that begins with the old failure prefix is successful',
    () async {
      const body =
          'Error decrypting: this is intentional synthetic note content';
      final fixture = await service.encrypt(body, password: password);
      final result = await service.decryptResult(fixture, password: password);
      expect(result.isSuccess, isTrue);
      expect(result.value, body);
      expect(await service.decrypt(fixture, password: password), body);
    },
  );

  test('empty app plaintext agrees between async and worker readers', () async {
    final iv = legacy.IV.fromUtf8('1234567890123456');
    final fixture = base64Encode(_cipher([], _appKey, iv));
    final asynchronous = await service.decryptAppResult(fixture);
    final synchronous = EncryptionService.decryptAppResultSync(fixture);
    expect(asynchronous.isSuccess, isTrue);
    expect(synchronous.isSuccess, isTrue);
    expect(asynchronous.value, '');
    expect(synchronous.value, '');
  });

  test(
    'empty binary payload succeeds without trying fallback credentials',
    () async {
      final result = await service.decryptBinaryResult(
        _binary([], _fixtureKey),
        password: password,
      );
      expect(result.isSuccess, isTrue);
      expect(result.value, isEmpty);
      expect(result.failure, isNull);
      expect(result.usedLegacyFallback, isFalse);
    },
  );

  test(
    'legacy default-key string fallback stays visible in its result',
    () async {
      const body = 'Synthetic mixed-key body';
      final result = await service.decryptResult(
        _text(body, _appKey),
        password: password,
      );
      expect(result.isSuccess, isTrue);
      expect(result.value, body);
      expect(result.usedLegacyFallback, isTrue);
    },
  );

  test('legacy empty default-key binary fallback is still a success', () async {
    final result = await service.decryptBinaryResult(
      _binary([], _appKey),
      password: password,
    );
    expect(result.isSuccess, isTrue);
    expect(result.value, isEmpty);
    expect(result.usedLegacyFallback, isTrue);
  });

  test('malformed framing has no string or binary payload', () async {
    for (final source in [
      '',
      'not-base64',
      'a:b:c',
      'AA==:AA==',
      '${_fixtureIv.base64}:',
    ]) {
      final result = await service.decryptResult(source);
      expect(result.isSuccess, isFalse);
      expect(result.value, isNull);
      expect(result.failure, DecryptionFailure.invalidCiphertext);
    }
    for (final length in [0, 15, 16, 17, 31, 33]) {
      final result = await service.decryptBinaryResult(Uint8List(length));
      expect(result.isSuccess, isFalse);
      expect(result.value, isNull);
    }
  });

  test('invalid final padding and aligned truncation are failures', () async {
    final damaged = _binary([1, 2, 3, 4, 5], _appKey);
    damaged[damaged.length - 1] ^=
        11; // SIC turns the final padding byte into zero.
    final truncated = _binary(List.filled(32, 0), _appKey);
    for (final source in [
      damaged,
      Uint8List.fromList(truncated.sublist(0, 32)),
    ]) {
      final result = await service.decryptBinaryResult(source);
      expect(result.isSuccess, isFalse);
      expect(result.value, isNull);
    }
  });

  test('wrong synthetic password never escapes as note content', () async {
    final result = await service.decryptResult(
      _text('Synthetic protected content', _fixtureKey),
      password: 'different-synthetic-password',
    );
    expect(result.isSuccess, isFalse);
    expect(result.value, isNull);
    expect(result.failure, DecryptionFailure.invalidCiphertext);
  });

  test('legacy key-derived IV text remains readable', () async {
    const body = 'Synthetic historical IV body';
    final result = await service.decryptResult(
      _text(body, _fixtureKey, noIvPrefix: true),
      password: password,
    );
    expect(result.isSuccess, isTrue);
    expect(result.value, body);
  });

  test('app failures have no payload in async or worker results', () async {
    for (final source in ['', 'not-base64', 'AA==']) {
      final asynchronous = await service.decryptAppResult(source);
      final synchronous = EncryptionService.decryptAppResultSync(source);
      expect(asynchronous.isSuccess, isFalse);
      expect(synchronous.isSuccess, isFalse);
      expect(asynchronous.value, isNull);
      expect(synchronous.value, isNull);
    }
  });
}
