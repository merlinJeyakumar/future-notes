import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/services/android_attachment_thumbnails.dart';
import 'support/thumbnail_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('thumbnail-ownership-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native JPEG avoids fallback; unavailable video needs granted source',
    () async {
      Object? reply = {'jpeg': thumbnailFixture(), 'fallback': false};
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'generate');
        expect(call.arguments['source'], 'cached');
        return reply;
      });
      final source = AndroidAttachmentThumbnails(
        channel: channel,
        fallback: (_) async {
          calls++;
          return thumbnailFixture();
        },
      );
      expect(
        await source.generate('cached', 'owned-cache', 'video'),
        thumbnailFixture(),
      );
      expect(calls, 0);
      reply = {'jpeg': null, 'fallback': false};
      expect(await source.generate('cached', 'owned-cache', 'video'), isNull);
      expect(calls, 0);
      reply = {'jpeg': null, 'fallback': true};
      expect(
        await source.generate('cached', 'owned-cache', 'video'),
        thumbnailFixture(),
      );
      expect(calls, 1);
    },
  );

  test(
    'bad source, image, and channel failure cannot authorize fallback',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'jpeg': null, 'fallback': true},
      );
      final source = AndroidAttachmentThumbnails(
        channel: channel,
        fallback: (_) async {
          calls++;
          return thumbnailFixture();
        },
      );
      expect(await source.generate('cached', 'owned-cache', 'image'), isNull);
      expect(await source.generate('other', 'unowned', 'video'), isNull);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'thumbnail_input'),
      );
      expect(await source.generate('picked', 'unowned', 'video'), isNull);
      expect(calls, 0);
    },
  );

  test('malformed fallback bytes are not stored as a thumbnail', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'jpeg': null, 'fallback': true},
    );
    final source = AndroidAttachmentThumbnails(
      channel: channel,
      fallback: (_) async => Uint8List.fromList([1, 2, 3]),
    );
    expect(await source.generate('picked', 'owned-source', 'video'), isNull);
  });
}
