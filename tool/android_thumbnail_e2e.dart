// Disposable real-SAF / production-decoder / persisted-thumbnail rendering probe.
// Never imported by main.dart; refuses any folder not created for this probe.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_file_actions.dart';
import 'package:flutter_application_1/core/platform/private_settings_store.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_strip.dart';
import 'package:flutter_application_1/features/dashboard/mobile/mobile_theme.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'thumbnail_fixture.dart';

class Preferences implements PrivateSettingsStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = Map.of(v);
  }
}

Uint8List integers(List<int> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setUint32(i * 4, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List chunk(String name, List<int> bytes) => Uint8List.fromList([
  ...ascii.encode(name),
  ...integers([bytes.length]),
  ...bytes,
  if (bytes.length.isOdd) 0,
]);
Uint8List avi() {
  const w = 64, h = 36, frameSize = w * h * 3, frames = 8;
  final main = integers([
    500000,
    frameSize * 2,
    0,
    16,
    frames,
    0,
    1,
    frameSize,
    w,
    h,
    0,
    0,
    0,
    0,
  ]);
  final stream = Uint8List(56);
  stream.setRange(0, 8, ascii.encode('vidsDIB '));
  final s = ByteData.sublistView(stream);
  for (final e in {
    20: 1,
    24: 2,
    32: frames,
    36: frameSize,
    40: 0xffffffff,
  }.entries) {
    s.setUint32(e.key, e.value, Endian.little);
  }
  s.setUint16(52, w, Endian.little);
  s.setUint16(54, h, Endian.little);
  final format = integers([40, w, h, (24 << 16) | 1, 0, frameSize, 0, 0, 0, 0]);
  final headers = chunk('LIST', [
    ...ascii.encode('hdrl'),
    ...chunk('avih', main),
    ...chunk('LIST', [
      ...ascii.encode('strl'),
      ...chunk('strh', stream),
      ...chunk('strf', format),
    ]),
  ]);
  final movie = <int>[...ascii.encode('movi')], index = <int>[];
  for (var i = 0; i < frames; i++) {
    index.addAll([
      ...ascii.encode('00db'),
      ...integers([16, movie.length, frameSize]),
    ]);
    movie.addAll(
      chunk(
        '00db',
        List.generate(frameSize, (p) => p % 3 == (i < 4 ? 2 : 1) ? 240 : 8),
      ),
    );
  }
  return chunk('RIFF', [
    ...ascii.encode('AVI '),
    ...headers,
    ...chunk('LIST', movie),
    ...chunk('idx1', index),
  ]);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: MobileTheme.dark, home: const Probe()));
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _Probe();
}

class _Probe extends State<Probe> {
  ContentViewModel? model;
  String status = 'Choose empty fn-thumbnail-e2e folder';
  Future<void> run() async {
    var stage = 0;
    try {
      const docs = MobileLibraryDocuments(
        kind: LibraryLocationKind.androidTree,
      );
      final location = await docs.selectLocalFolder();
      if (location == null) return;
      final root = await docs.root(location);
      if (!root.name.startsWith('fn-thumbnail-e2e-'))
        throw StateError('folder');
      final existing = await docs.children(location, root);
      stage = 1;
      final actions = MobileFileActions();
      final run = await Directory(
        '${await actions.privateRoot()}/future-notes-validation-thumbnail-e2e-${const Uuid().v4()}',
      ).create();
      final settings = SettingsService.withStorage(
        storage: StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: '${run.path}/library',
          settingsFile: '${run.path}/settings/config.json',
        ),
        privateSettings: Preferences(),
        documentsDirectoryResolver: () async => run,
      );
      await settings.init();
      final files = ProviderNoteFiles(
        documents: docs,
        location: location,
        libraryId: const Uuid().v4(),
        privateRoot: '${run.path}/provider',
      );
      await files.initialize();
      final cipher = EncryptionService(useNative: false);
      if (existing.isNotEmpty) {
        final saved = existing.where((e) => e.name.startsWith('note_')).single;
        final restoredCache = AttachmentOpenCache(
          rootResolver: () => actions.cacheRoot(),
          sourceResolver: (n, id) => files.attachmentSource(n, id),
        );
        final restored = ContentViewModel(
          fileService: files,
          settings: settings,
          encryptionService: cipher,
          attachmentOpenCache: restoredCache,
          startBackgroundServices: false,
        );
        if (!(await restored.loadNote(saved.name)).isSuccess ||
            !await restored.unlockNote('demo'))
          throw StateError('restart');
        for (final a in restored.attachments) {
          final bytes = await restored.restoreAttachmentThumbnail(a);
          if (bytes == null) throw StateError('restart-restore');
          final c = await ui.instantiateImageCodec(bytes);
          final f = await c.getNextFrame();
          f.image.dispose();
          c.dispose();
        }
        print(
          'FN_E2E_RESTART decoded=${restored.attachments.length} transforms=${restoredCache.transformCount}',
        );
        setState(() {
          model = restored;
          status = 'Restored after restart without payload decryption';
        });
        print('FN_E2E_READY');
        return;
      }
      var reference = await files.newNoteReference(const Uuid().v4());
      final entries = <AttachmentModel>[],
          prepared = <PreparedAttachmentFile>[];
      final fixtures = [
        base64Decode(imageFixture),
        base64Decode(videoFixture),
        avi(),
      ];
      for (var i = 0; i < fixtures.length; i++) {
        final id = const Uuid().v4(),
            name = ['Demo.png', 'Short.mp4', 'Three seconds.avi'][i];
        final encrypted = await cipher.encryptBinary(
          fixtures[i],
          password: 'demo',
        );
        final file = await File('${run.path}/$id.med').writeAsBytes(encrypted);
        entries.add(
          AttachmentModel(id: id, fileName: name, size: fixtures[i].length),
        );
        prepared.add(
          PreparedAttachmentFile(
            id,
            StreamingFileSource(file.path, encrypted.length),
            fileName: name,
          ),
        );
      }
      final note = NoteModel(
        id: reference.modelId!,
        title: 'Synthetic thumbnail roundtrip',
        content: await cipher.encrypt('Synthetic only', password: 'demo'),
        isLocked: true,
        timestamp: 1700000000000,
        attachments: entries,
      );
      reference = await files.commitGeneration(
        reference,
        await cipher.encryptApp(jsonEncode(note.toJson())),
        prepared,
      );
      stage = 2;
      AttachmentOpenCache cache() => AttachmentOpenCache(
        rootResolver: () => actions.cacheRoot(),
        sourceResolver: (n, id) => files.attachmentSource(n, id),
      );
      ContentViewModel editor(AttachmentOpenCache c) => ContentViewModel(
        fileService: files,
        settings: settings,
        encryptionService: cipher,
        attachmentOpenCache: c,
        startBackgroundServices: false,
      );
      final firstCache = cache();
      final first = editor(firstCache);
      if (!(await first.loadNote(reference.fileName)).isSuccess ||
          !await first.unlockNote('demo'))
        throw StateError('load');
      final result = await first.refreshAttachmentThumbnails();
      print(
        'FN_E2E_REFRESH success=${result.isSuccess} stored=${first.attachments.where((a) => a.encryptedThumbnail != null).length} transforms=${firstCache.transformCount}',
      );
      if (!result.isSuccess ||
          first.attachments.any((a) => a.encryptedThumbnail == null))
        throw StateError('refresh');
      stage = 3;
      final video = await first.restoreAttachmentThumbnail(
        first.attachments.last,
      );
      final codec = await ui.instantiateImageCodec(video!);
      final frame = await codec.getNextFrame();
      final rgba = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset =
          ((frame.image.height ~/ 2) * frame.image.width +
              frame.image.width ~/ 2) *
          4;
      final green = rgba.getUint8(offset + 1) > rgba.getUint8(offset) + 80;
      frame.image.dispose();
      codec.dispose();
      print('FN_E2E_THREE_SECONDS green=$green');
      if (!green) throw StateError('frame');
      await firstCache.invalidateNote(reference);
      final secondCache = cache();
      final second = editor(secondCache);
      if (!(await second.loadNote(reference.fileName)).isSuccess ||
          !await second.unlockNote('demo'))
        throw StateError('reload');
      for (final a in second.attachments) {
        final bytes = await second.restoreAttachmentThumbnail(a);
        if (bytes == null) throw StateError('restore');
        final c = await ui.instantiateImageCodec(bytes);
        final f = await c.getNextFrame();
        f.image.dispose();
        c.dispose();
      }
      print('FN_E2E_RELOAD decoded=3 transforms=${secondCache.transformCount}');
      setState(() {
        model = second;
        status = 'Three stored thumbnails restored; green video at 3 seconds';
      });
      print('FN_E2E_READY');
    } catch (e) {
      print('FN_E2E_FAILED stage=$stage type=${e.runtimeType}');
      setState(() => status = 'Failed stage $stage');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Synthetic thumbnail roundtrip')),
    body: Column(
      children: [
        Text(status),
        if (model == null)
          FilledButton(
            onPressed: run,
            child: const Text('Choose synthetic folder'),
          ),
        if (model != null)
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AttachmentStrip(viewModel: model!),
            ),
          ),
      ],
    ),
  );
}
