// Explicit synthetic device check; never imported by the normal application.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_file_actions.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_job_binding.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/mobile/shared_attachment_jobs.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/auto_save_policy.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

class _ScopedDocuments extends MobileLibraryDocuments {
  _ScopedDocuments(this.scope) : super(kind: LibraryLocationKind.androidTree);
  final LibraryDocument scope;
  @override
  Future<LibraryDocument> root(LibraryLocation library) async => scope;
}

void check(bool condition, String code) {
  if (!condition) throw StateError(code);
}

Future<void> until(bool Function() done, String code) async {
  final limit = DateTime.now().add(const Duration(seconds: 100));
  while (!done()) {
    check(DateTime.now().isBefore(limit), code);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Synthetic sharing check'))),
    ),
  );
  final report = <String, Object?>{'passed': false};
  const base = MobileLibraryDocuments(kind: LibraryLocationKind.androidTree);
  final scopeName = '.future-notes-validation-share-${const Uuid().v4()}';
  report['syntheticScopeName'] = scopeName;
  LibraryLocation? location;
  LibraryDocument? scope;
  Directory? run;
  ProviderNoteFiles? files;
  ContentViewModel? model;
  SettingsService? settings;
  SharedAttachmentJobs? shares;
  MobileJobBinding? binding;
  try {
    AndroidNativeCipher.initialize(ServicesBinding.rootIsolateToken);
    final selection = await MobileFileActions.channel.invokeMethod<String>(
      'readLibrarySelection',
    );
    check(selection != null, 'selection-required');
    location = LibraryLocation.fromJson(
      Map<String, Object?>.from(
        (jsonDecode(selection!) as Map)['location'] as Map,
      ),
    );
    run = await (await getTemporaryDirectory()).createTemp(
      'future-notes-validation-share-',
    );
    run = Directory(await run.resolveSymbolicLinks());
    scope = await base.create(
      location,
      await base.root(location),
      scopeName,
      directory: true,
    );
    check(scope.name == scopeName, 'scope-name-changed');
    files = ProviderNoteFiles(
      documents: _ScopedDocuments(scope),
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
    model = ContentViewModel(
      fileService: files,
      settings: settings,
      encryptionService: EncryptionService(),
      startBackgroundServices: false,
      autoSavePolicy: AutoSavePolicy.mobile,
    );
    shares = SharedAttachmentJobs(
      model: model,
      files: files,
      settings: settings,
    );
    binding = MobileJobBinding(model, additional: shares);
    await binding.interrupted;
    final receiver = shares;
    print('FN_SHARE_READY_CANCEL');
    await until(
      () => receiver.batches.value.isNotEmpty,
      'cancel-share-timeout',
    );
    final unsubmitted = receiver.batches.value.single;
    check(unsubmitted.sources.length == 2, 'multi-source-count');
    check(
      unsubmitted.sources[0]['name'] == unsubmitted.sources[1]['name'],
      'duplicate-display-names',
    );
    await receiver.discard(unsubmitted);
    check(
      (await receiver.inbox.pending()).isEmpty && receiver.jobs.value.isEmpty,
      'cancel-intake-mutated',
    );
    report['cancelBeforeSubmit'] = true;
    final target = await model.createSharedNote(
      'Synthetic share target',
      'synthetic-password',
    );
    final other = await model.createSharedNote('Synthetic other note', null);
    check(
      (await model.loadNote(other.reference.fileName)).isSuccess,
      'other-note-load',
    );
    // Keep this fixture deliberately unsaved rather than racing normal autosave.
    model.setAutomaticSavingActive(false);
    model.quillController.document.insert(0, 'Unpublished other draft');
    model.quillController.updateSelection(
      const TextSelection.collapsed(offset: 5),
      ChangeSource.local,
    );
    final delta = model.quillController.document.toDelta().toJson();
    var changedBytes = false;
    final observed = <String>{};
    receiver.jobs.addListener(() {
      for (final state in receiver.jobs.value) {
        if (observed.add(state.progress.value.id)) {
          state.progress.addListener(() {
            final job = state.progress.value;
            if (job.bytes > 0 && job.active) changedBytes = true;
          });
        }
      }
    });
    print('FN_SHARE_READY_START');
    await until(() => receiver.batches.value.isNotEmpty, 'share-timeout');
    final watch = Stopwatch()..start();
    await receiver.start(receiver.batches.value.single, target);
    check(
      model.currentContentPath == other.reference.contentPath,
      'start-reset-editor',
    );
    await until(() => !receiver.hasActive, 'attach-timeout');
    check(
      receiver.jobs.value.length == 2 &&
          receiver.jobs.value.every(
            (s) => s.progress.value.phase == AttachmentJobPhase.completed,
          ),
      'attachment-job-failed',
    );
    report['bodyPreserved'] =
        jsonEncode(model.quillController.document.toDelta().toJson()) ==
        jsonEncode(delta);
    report['caretPreserved'] = model.quillController.selection.baseOffset == 5;
    report['draftStillDirty'] = model.draftSession.isDirty;
    check(
      report['bodyPreserved'] == true &&
          report['caretPreserved'] == true &&
          report['draftStillDirty'] == true,
      'background-draft-changed',
    );
    final fresh = await model.prepareSharedTarget(target.reference.fileName);
    check(
      fresh.decoded.note.id == target.decoded.note.id &&
          fresh.decoded.note.attachments.length == 2,
      'publication-metadata',
    );
    check(
      fresh.decoded.note.attachments.map((a) => a.id).toSet().length == 2,
      'duplicate-name-collision',
    );
    report['twoFilesAttached'] = true;
    report['progressAdvanced'] = changedBytes;
    report['otherDraftAndCaretPreserved'] = true;
    report['attachMilliseconds'] = watch.elapsedMilliseconds;
    report['bytesAttached'] = fresh.decoded.note.attachments.fold<int>(
      0,
      (n, a) => n + a.size,
    );
    print('FN_SHARE_READY_JOB_CANCEL');
    await until(
      () => receiver.batches.value.isNotEmpty,
      'job-cancel-share-timeout',
    );
    await receiver.start(receiver.batches.value.single, target);
    await receiver.cancel(receiver.jobs.value.last.progress.value.id);
    await until(() => !receiver.hasActive, 'job-cancel-timeout');
    check(
      receiver.jobs.value.last.progress.value.phase ==
          AttachmentJobPhase.cancelled,
      'job-cancel-result',
    );
    check(
      (await model.prepareSharedTarget(
            target.reference.fileName,
          )).decoded.note.attachments.length ==
          2,
      'cancel-published',
    );
    report['cancelAfterSubmit'] = true;
    check((await model.saveNote()).isSuccess, 'fixture-save');
    print('FN_SHARE_READY_IMPORT');
    await until(
      () => receiver.batches.value.isNotEmpty,
      'package-share-timeout',
    );
    final packageBatch = receiver.batches.value.single;
    check(packageBatch.notePackages.length == 1, 'package-detection');
    final selected = await receiver.takePackage(
      packageBatch,
      packageBatch.notePackages.single,
    );
    try {
      check(
        receiver.batches.value.single.sources.length == 1,
        'remaining-share-lost',
      );
      final verification = await model.verifyImportFile(selected);
      check(
        verification.isValid &&
            verification.isPack &&
            !verification.isPackEncrypted,
        'package-header-validation',
      );
      final imported = await model.importNoteFile(
        selected.path!,
        resolveConflict: (_) async => throw StateError('unexpected-conflict'),
      );
      check(
        imported.isSuccess &&
            imported.value!.disposition == NoteImportDisposition.created,
        'shared-package-import',
      );
      report['sharedPackageImported'] = true;
      report['otherSharedSourceRetained'] = true;
    } finally {
      await model.releaseImportSelection(selected);
    }
    await receiver.discard(receiver.batches.value.single);
    // A normal completed import retires its source lease. Share again exactly
    // as a user would to exercise the matching-UID decision with a fresh grant.
    print('FN_SHARE_READY_IMPORT_AGAIN');
    await until(
      () => receiver.batches.value.isNotEmpty,
      'repeat-package-share-timeout',
    );
    final repeatedBatch = receiver.batches.value.single;
    final repeated = await receiver.takePackage(
      repeatedBatch,
      repeatedBatch.notePackages.single,
    );
    try {
      var asked = false;
      final ignored = await model.importNoteFile(
        repeated.path!,
        resolveConflict: (_) async {
          asked = true;
          return NoteImportDecision.ignore;
        },
      );
      check(
        asked &&
            ignored.isSuccess &&
            ignored.value!.disposition == NoteImportDisposition.ignored,
        'shared-package-duplicate',
      );
      report['sharedPackageDuplicateOptions'] = true;
    } finally {
      await model.releaseImportSelection(repeated);
    }
    await receiver.discard(receiver.batches.value.single);
    report['passed'] = changedBytes;
  } catch (error) {
    report['failureType'] = error.runtimeType.toString();
    if (error is StateError && RegExp(r'^[a-z-]+$').hasMatch(error.message))
      report['failureCode'] = error.message;
  } finally {
    try {
      await shares?.close();
      binding?.dispose();
      shares?.dispose();
      model?.dispose();
      await model?.closeLibraryResources();
      await files?.close();
      await settings?.closePersistence();
      if (scope != null && location != null && scope.name == scopeName) {
        Future<void> remove(LibraryDocument document) async {
          for (var attempt = 0; attempt < 3; attempt++) {
            if (document.isDirectory) {
              for (final child in await base.children(location!, document)) {
                await remove(child);
              }
            }
            try {
              await base.delete(location!, document);
              return;
            } on LibraryAccessException catch (error) {
              if (error.code != 'not_empty' || attempt == 2) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
          }
        }

        await remove(scope);
        report['providerCleanupPassed'] = true;
      }
      if (run != null) {
        check(
          run.path.startsWith(
                '${await (await getTemporaryDirectory()).resolveSymbolicLinks()}/',
              ) &&
              run.path
                  .split('/')
                  .last
                  .startsWith('future-notes-validation-share-'),
          'invalid-private-cleanup',
        );
        await run.delete(recursive: true);
      }
    } catch (error) {
      report['cleanupFailed'] = true;
      report['cleanupType'] = error.runtimeType.toString();
      if (error is LibraryAccessException) report['cleanupCode'] = error.code;
      report['passed'] = false;
    }
  }
  print('FN_SHARE_PROBE ${jsonEncode(report)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            report['passed'] == true
                ? 'Synthetic sharing check passed'
                : 'Synthetic sharing check failed',
          ),
        ),
      ),
    ),
  );
}
