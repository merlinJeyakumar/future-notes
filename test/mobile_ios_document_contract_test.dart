import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/additional_mobile_jobs.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_job_binding.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_events.dart';
import 'package:flutter_application_1/core/storage/library_admission_probe.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/editor_harness.dart';
import 'support/memory_library_documents.dart';

const _library = LibraryLocation(
  kind: LibraryLocationKind.appleBookmark,
  token: 'opaque-synthetic-bookmark',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Apple admission accepts only the typed name collision and cleans probes',
    () async {
      final bridge = _DocumentBridge();
      await bridge.seedExisting();
      bridge.install();
      addTearDown(bridge.uninstall);

      await LibraryAdmissionProbe(bridge.adapter).verify(_library);

      expect(bridge.collisionCount, 1);
      expect(bridge.memory.nodes.length, 2);
      final existing = await bridge.memory.stat(_library, bridge.existing!);
      expect(
        await bridge.memory.read(_library, existing, offset: 0, length: 3),
        [9, 8, 7],
      );
      expect(bridge.readNames, everyElement(isNot('note_existing')));
      expect(bridge.deletedNames, isNot(contains('note_existing')));
    },
  );

  test(
    'generic native failure cannot be mistaken for a safe collision',
    () async {
      final bridge = _DocumentBridge(collisionCode: 'native_document_failed');
      await bridge.seedExisting();
      bridge.install();
      addTearDown(bridge.uninstall);

      await expectLater(
        LibraryAdmissionProbe(bridge.adapter).verify(_library),
        throwsA(
          isA<LibraryAccessException>().having(
            (error) => error.code,
            'code',
            'native_document_failed',
          ),
        ),
      );
      expect(bridge.memory.nodes.length, 2);
      expect(bridge.deletedNames, isNot(contains('note_existing')));
    },
  );

  for (final code in ['permission_revoked', 'full_disk', 'missing_document']) {
    test(
      'Apple document channel preserves $code without admitting the folder',
      () async {
        const channel = MethodChannel('synthetic/apple-document-failure');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: code,
            message: 'Synthetic storage error.',
          );
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        const adapter = MobileLibraryDocuments(
          kind: LibraryLocationKind.appleBookmark,
          channel: channel,
        );

        await expectLater(
          LibraryAdmissionProbe(adapter).verify(_library),
          throwsA(
            isA<LibraryAccessException>()
                .having((error) => error.code, 'code', code)
                .having(
                  (error) => error.message,
                  'message',
                  'Synthetic storage error.',
                ),
          ),
        );
      },
    );
  }

  test(
    'Apple direct output remains unsupported, retaining transfer fallback',
    () async {
      const adapter = MobileLibraryDocuments(
        kind: LibraryLocationKind.appleBookmark,
      );
      await expectLater(
        adapter.openOutputSink(_library, _rootDocument, 'candidate.pending'),
        throwsA(
          isA<LibraryAccessException>().having(
            (error) => error.code,
            'code',
            'unsupported_sink',
          ),
        ),
      );
    },
  );

  test(
    'library hints are scoped and final unsubscribe removes only its watch',
    () async {
      const channel = MethodChannel('synthetic/apple-library-events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final events = MobileLibraryEventChannel(channel: channel);
      var first = 0;
      var second = 0;
      var other = 0;
      final stopFirst = events.listen(_library.token, () => first++);
      final stopSecond = events.listen(_library.token, () => second++);
      final stopOther = events.listen('other-bookmark', () => other++);
      await _sendNative(channel, 'changed', _library.token);
      expect((first, second, other), (1, 1, 0));

      await stopFirst();
      expect(calls.where((call) => call.method == 'unwatch'), isEmpty);
      await _sendNative(channel, 'changed', _library.token);
      expect((first, second, other), (1, 2, 0));
      await stopSecond();
      expect(calls.where((call) => call.method == 'unwatch').single.arguments, {
        'library': _library.token,
      });
      await _sendNative(channel, 'changed', _library.token);
      await _sendNative(channel, 'changed', 'other-bookmark');
      expect((first, second, other), (1, 2, 1));
      await stopOther();
      expect(calls.where((call) => call.method == 'unwatch'), hasLength(2));
    },
  );

  testWidgets('expiration cancels safe work and reports the correct system', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    const channel = MethodChannel('future_notes/jobs');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'interruptedJobs' ? '[]' : null,
    );
    final additional = _AdditionalJobs();
    final binding = MobileJobBinding(h.editor, additional: additional);
    await binding.interrupted;
    try {
      await _sendNative(channel, 'timeout', null);
      expect(additional.cancelled, ['cancellable']);
      expect(
        h.editor.operationResultNotifier.value?.message,
        Platform.isAndroid
            ? startsWith('Android ended')
            : startsWith('The system ended'),
      );
      expect(h.files.writes, isEmpty);
      expect(binding.retained.value, isEmpty);
    } finally {
      binding.dispose();
      additional.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await tester.runAsync(h.dispose);
    }
  });
}

Future<void> _sendNative(
  MethodChannel channel,
  String method,
  Object? arguments,
) async {
  final response = Completer<void>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {
          response.complete();
        },
      );
  await response.future;
}

const _rootDocument = LibraryDocument(
  token: 'root',
  name: 'root',
  isDirectory: true,
  length: 0,
  modifiedMillis: 1,
);

/// Exercises the real Dart adapter/admission protocol, not Swift source text.
/// Native NSError classification still requires its separate Apple host gate.
class _DocumentBridge {
  _DocumentBridge({this.collisionCode = 'name_exists'});
  final String collisionCode;
  final memory = MemoryLibraryDocuments();
  static const channel = MethodChannel('synthetic/apple-document-probe');
  final adapter = const MobileLibraryDocuments(
    kind: LibraryLocationKind.appleBookmark,
    channel: channel,
  );
  final _documents = <String, LibraryDocument>{'root': _rootDocument};
  final readNames = <String>[];
  final deletedNames = <String>[];
  var collisionCount = 0;
  LibraryDocument? existing;

  Future<void> seedExisting() async {
    existing = await memory.create(_library, _rootDocument, 'note_existing');
    await memory.append(
      _library,
      existing!,
      Uint8List.fromList([9, 8, 7]),
      offset: 0,
    );
  }

  void install() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(channel, _call);
  void uninstall() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);

  Map<String, Object?> _json(LibraryDocument document) {
    _documents[document.token] = document;
    return {
      'token': document.token,
      'name': document.name,
      'directory': document.isDirectory,
      'length': document.length,
      'modified': document.modifiedMillis,
    };
  }

  Future<Object?> _call(MethodCall call) async {
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    expect(args['library'], _library.token);
    if (call.method == 'root') return _json(await memory.root(_library));
    final document = _documents[args['document']]!;
    try {
      switch (call.method) {
        case 'create':
          return _json(
            await memory.create(
              _library,
              document,
              args['name'] as String,
              directory: args['directory'] == true,
            ),
          );
        case 'append':
          await memory.append(
            _library,
            document,
            args['bytes'] as Uint8List,
            offset: args['offset'] as int,
          );
          return null;
        case 'read':
          readNames.add(document.name);
          return memory.read(
            _library,
            document,
            offset: args['offset'] as int,
            length: args['length'] as int,
          );
        case 'flush':
          await memory.flush(_library, document);
          return null;
        case 'rename':
          return _json(
            await memory.rename(_library, document, args['name'] as String),
          );
        case 'children':
          return (await memory.children(
            _library,
            document,
          )).map(_json).toList();
        case 'delete':
          deletedNames.add(document.name);
          await memory.delete(_library, document);
          return null;
        default:
          throw StateError('Unexpected document method ${call.method}');
      }
    } on LibraryAccessException catch (error) {
      if (error.code == 'name_exists') collisionCount++;
      throw PlatformException(
        code: error.code == 'name_exists' ? collisionCode : error.code,
        message: 'Synthetic document operation failed.',
      );
    }
  }
}

class _AdditionalJobs implements AdditionalMobileJobs {
  @override
  final ValueNotifier<List<AttachmentJobState>> jobs = ValueNotifier([
    for (final (id, phase) in [
      ('cancellable', AttachmentJobPhase.encrypting),
      ('committing', AttachmentJobPhase.finalizing),
      ('completed', AttachmentJobPhase.completed),
    ])
      AttachmentJobState(
        AttachmentJobSnapshot(
          id: id,
          owner: 1,
          fileName: 'Synthetic task',
          phase: phase,
        ),
      ),
  ]);
  final cancelled = <String>[];
  @override
  Future<void> cancel(String id) async => cancelled.add(id);
  @override
  Map<String, Object?>? recovery(String id) => null;
  void dispose() {
    for (final job in jobs.value) {
      job.dispose();
    }
    jobs.dispose();
  }
}
