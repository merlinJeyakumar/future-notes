// Synthetic native-device validation only. Never loaded by lib/main.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_file_actions.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/auto_save_policy.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/mobile_theme.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_discovery.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'package:flutter_quill/flutter_quill.dart';

class _Documents extends MobileLibraryDocuments {
  _Documents(this.scope) : super(kind: LibraryLocationKind.androidTree);
  final LibraryDocument scope;
  int readBytes = 0;
  @override
  Future<LibraryDocument> root(LibraryLocation library) async => scope;
  @override
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  }) async {
    final bytes = await super.read(
      library,
      document,
      offset: offset,
      length: length,
    );
    readBytes += bytes.length;
    return bytes;
  }
}

void check(bool value, String code) {
  if (!value) throw StateError(code);
}

Future<void> until(
  bool Function() predicate,
  String code, {
  int seconds = 45,
}) async {
  final timer = Stopwatch()..start();
  while (!predicate() && timer.elapsed < Duration(seconds: seconds)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  check(predicate(), code);
}

bool? shelfVisible() {
  bool? visible;
  void visit(Element e) {
    if (e.widget case final Visibility widget
        when widget.key == const ValueKey('mobile-attachment-shelf'))
      visible = widget.visible;
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return visible;
}

EditorState? richEditor() {
  EditorState? state;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is QuillEditor) state = widget.config.editorKey?.currentState;
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return state;
}

Future<DiscoverySnapshot> scan(ProviderDiscovery discovery, String root) async {
  final next = discovery.discoveriesStream.first;
  discovery.loadRecentFiles(root);
  return next.timeout(const Duration(seconds: 30));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Synthetic mobile editing check')),
      ),
    ),
  );
  final report = <String, Object?>{'passed': false, 'stage': 0};
  const base = MobileLibraryDocuments(kind: LibraryLocationKind.androidTree);
  LibraryLocation? location;
  LibraryDocument? scope;
  Directory? run;
  ProviderNoteFiles? files;
  ContentViewModel? model;
  ProviderDiscovery? discovery;
  SettingsService? settings;
  final scopeName = '.future-notes-validation-editing-${const Uuid().v4()}';
  try {
    AndroidNativeCipher.initialize(ServicesBinding.rootIsolateToken);
    final selection = await MobileFileActions.channel.invokeMethod<String>(
      'readLibrarySelection',
    );
    check(selection != null, 'library-selection-required');
    location = LibraryLocation.fromJson(
      Map<String, Object?>.from(
        (jsonDecode(selection!) as Map)['location'] as Map,
      ),
    );
    scope = await base.create(
      location,
      await base.root(location),
      scopeName,
      directory: true,
    );
    check(scope.name == scopeName, 'scope-name-changed');
    run = await (await getTemporaryDirectory()).createTemp(
      'future-notes-validation-editing-',
    );
    run = Directory(await run.resolveSymbolicLinks());
    final docs = _Documents(scope);
    files = ProviderNoteFiles(
      documents: docs,
      location: location,
      libraryId: const Uuid().v4(),
      privateRoot: run.path,
    );
    await files.initialize();
    settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: '${run.path}/library',
        settingsFile: '${run.path}/configuration/settings.json',
      ),
    );
    await settings.init();
    final cipher = EncryptionService();
    final reference = await files.newNoteReference(const Uuid().v4());
    final id = reference.fileName.substring(5);
    await files.writeResolved(
      reference,
      await cipher.encryptApp(
        jsonEncode({
          'id': id,
          'title': 'Synthetic mobile editing',
          'content': await cipher.encrypt(
            'Synthetic body\n',
            password: 'synthetic-password',
          ),
          'isLocked': true,
          'timestamp': 1700000000000,
          'attachments': [],
        }),
      ),
    );
    discovery = ProviderDiscovery(files);
    final editor = ContentViewModel(
      fileService: files,
      settings: settings,
      encryptionService: cipher,
      backgroundService: discovery,
      autoSavePolicy: AutoSavePolicy.mobile,
    );
    model = editor;
    check(
      (await editor.loadNote(reference.fileName)).isSuccess,
      'synthetic-note-open',
    );
    check(
      await editor.unlockNote('synthetic-password'),
      'synthetic-note-unlock',
    );
    runApp(
      MaterialApp(
        theme: MobileTheme.dark,
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        supportedLocales: FlutterQuillLocalizations.supportedLocales,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: editor,
            builder: (_, _) => MobileContentArea(viewModel: editor),
          ),
        ),
      ),
    );
    await until(
      () =>
          editor.recentFiles.length == 1 &&
          !editor.noteListStateNotifier.value.updating,
      'initial-list',
    );
    final detachedDiscovery = ProviderDiscovery(files);
    try {
      final first = await scan(detachedDiscovery, files.binding.root);
      final beforeRead = docs.readBytes;
      final second = await scan(detachedDiscovery, files.binding.root);
      check(
        identical(first.files.single, second.files.single) &&
            docs.readBytes == beforeRead,
        'unchanged-hint-read-note',
      );
      report['unchangedHintReadBytes'] = docs.readBytes - beforeRead;
    } finally {
      detachedDiscovery.dispose();
    }
    report['stage'] = 1;
    var saves = 0;
    final commitClock = Stopwatch();
    final commitMicros = <int>[];
    void saving() {
      if (editor.isSavingNotifier.value) {
        saves++;
        commitClock
          ..reset()
          ..start();
      } else if (commitClock.isRunning) {
        commitMicros.add(commitClock.elapsedMicroseconds);
        commitClock.stop();
      }
    }

    editor.isSavingNotifier.addListener(saving);
    if (!const bool.fromEnvironment('FN_EDITING_INPUT_PROBE')) {
      editor.titleController.text = 'Synthetic first edit';
      await Future<void>.delayed(const Duration(seconds: 10));
      check(saves == 0, 'autosave-before-idle');
      editor.quillController.document.insert(0, 'Synthetic continued typing ');
      await Future<void>.delayed(const Duration(seconds: 10));
      check(saves == 0, 'typing-restarted-idle');
      await until(
        () =>
            saves == 1 &&
            !editor.draftSession.isDirty &&
            !editor.isSavingNotifier.value,
        'first-autosave',
      );
      editor.quillController.document.insert(0, 'Synthetic next edit ');
      await Future<void>.delayed(const Duration(seconds: 16));
      check(saves == 1, 'autosave-cadence');
      await until(
        () =>
            saves == 2 &&
            !editor.draftSession.isDirty &&
            !editor.isSavingNotifier.value,
        'second-autosave',
      );
      report['idleAndCadencePassed'] = true;
    }
    report['stage'] = 2;
    final document = editor.quillController.document;
    check(!editor.quillController.readOnly, 'editor-readonly');
    editor.quillController.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    editor.quillController.skipRequestKeyboard = false;
    editor.focusNode.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    final rich = richEditor();
    check(rich != null, 'rich-editor-not-mounted');
    rich!.requestKeyboard();
    await until(
      () =>
          WidgetsBinding
              .instance
              .platformDispatcher
              .views
              .first
              .viewInsets
              .bottom >
          0,
      'keyboard-not-visible',
      seconds: 10,
    );
    await until(
      () => shelfVisible() == false,
      'keyboard-shelf-visible',
      seconds: 5,
    );
    editor.focusNode.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await until(
      () =>
          shelfVisible() == true &&
          WidgetsBinding
                  .instance
                  .platformDispatcher
                  .views
                  .first
                  .viewInsets
                  .bottom ==
              0,
      'keyboard-shelf-not-restored',
      seconds: 5,
    );
    check(
      identical(document, editor.quillController.document),
      'editor-recreated',
    );
    report['realKeyboardShelfPassed'] = true;
    var unsolicitedLoading = false;
    void listing() {
      if (editor.noteListStateNotifier.value.updating)
        unsolicitedLoading = true;
    }

    editor.noteListStateNotifier.addListener(listing);
    final input = await File(
      '${run.path}/demo.txt',
    ).writeAsString('Synthetic attachment only');
    check(
      (await editor.addOwnedAttachment(input.path, 'demo.txt')).isSuccess,
      'attachment-commit',
    );
    check(
      !editor.draftSession.isDirty && !editor.isSavingNotifier.value,
      'attachment-left-dirty',
    );
    final afterAttachment = saves;
    await Future<void>.delayed(const Duration(seconds: 17));
    check(saves == afterAttachment, 'attachment-triggered-extra-save');
    check(!unsolicitedLoading, 'background-list-loading');
    editor.noteListStateNotifier.removeListener(listing);
    report['attachmentNoExtraSavePassed'] = true;
    report['quietRefreshPassed'] = true;
    report['commitMicros'] = commitMicros;
    report['stage'] = 3;
    editor.setAutomaticSavingActive(false);
    editor.titleController.text = 'Synthetic background edit';
    await Future<void>.delayed(const Duration(seconds: 16));
    check(
      saves == afterAttachment && editor.draftSession.isDirty,
      'background-autosave',
    );
    check((await editor.saveNote()).isSuccess, 'explicit-save');
    check(!editor.draftSession.isDirty, 'explicit-save-left-dirty');
    editor.isSavingNotifier.removeListener(saving);
    report['backgroundAndExplicitSavePassed'] = true;
    report['passed'] = true;
  } catch (error) {
    report['failureType'] = error.runtimeType.toString();
    if (error is StateError && RegExp(r'^[a-z-]+$').hasMatch(error.message))
      report['failureCode'] = error.message;
  } finally {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Synthetic editing check finished')),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    model?.dispose();
    await model?.closeLibraryResources();
    discovery?.dispose();
    await files?.close();
    await settings?.closePersistence();
    try {
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
        final parent = await (await getTemporaryDirectory())
            .resolveSymbolicLinks();
        check(
          run.path.startsWith('$parent/') &&
              run.path
                  .split('/')
                  .last
                  .startsWith('future-notes-validation-editing-'),
          'private-cleanup-scope',
        );
        await run.delete(recursive: true);
      }
    } catch (_) {
      report['cleanupFailed'] = true;
    }
  }
  print('FN_EDITING_PROBE ${jsonEncode(report)}');
}
