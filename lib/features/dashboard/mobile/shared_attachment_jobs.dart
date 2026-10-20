import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../../../core/platform/additional_mobile_jobs.dart';
import '../../../core/platform/incoming_share_inbox.dart';
import '../../../core/platform/library_documents.dart';
import '../../../core/platform/mobile_diagnostics.dart';
import '../../../core/storage/attachment_transform_worker.dart';
import '../../../core/storage/streaming_file_cipher.dart';
import '../../../core/storage/owned_note_persistence.dart';
import '../models/attachment_job.dart';
import '../models/note_model.dart';
import '../models/shared_attachment_target.dart';
import '../services/provider_note_files.dart';
import '../services/settings_service.dart';
import '../viewmodels/content_viewmodel.dart';

/// Mobile job lifetime is independent of the editor's current note/session.
class SharedAttachmentJobs implements AdditionalMobileJobs {
  SharedAttachmentJobs({
    required this.model,
    required this.files,
    required this.settings,
    IncomingShareInbox? inbox,
  }) : inbox = inbox ?? IncomingShareInbox() {
    this.inbox.listen(() => unawaited(refreshInbox()));
    model.addListener(_checkCredentials);
  }
  final ContentViewModel model;
  final ProviderNoteFiles files;
  final SettingsService settings;
  final IncomingShareInbox inbox;
  @override
  final ValueNotifier<List<AttachmentJobState>> jobs =
      ValueNotifier<List<AttachmentJobState>>([]);
  final batches = ValueNotifier<List<IncomingSharedBatch>>([]);
  final worker = AttachmentTransformWorker();
  final _transforms = <String, FileTransformJob>{};
  final _targets = <String, SharedAttachmentTarget>{};
  final _recoveries = <String, Map<String, Object?>>{};
  final _cancelled = <String>{};
  final _running = <Future<void>>{};
  final _submitted = <String>{};
  bool _closed = false;
  bool get hasActive => jobs.value.any((s) => s.progress.value.active);
  bool activeFor(String fileName) => jobs.value.any(
    (s) =>
        s.progress.value.active &&
        _targets[s.progress.value.id]?.reference.fileName == fileName,
  );
  Future<void> refreshInbox() async {
    try {
      final pending = await inbox.pending();
      if (!_closed)
        batches.value = pending
            .where((b) => !_submitted.contains(b.id))
            .toList();
    } on Exception {
      /* Native pending receipt remains authoritative until the UI retries. */
    }
  }

  Future<void> discard(IncomingSharedBatch batch) async {
    await inbox.discard(batch.id);
    await refreshInbox();
  }

  /// Transfer only the selected package; other shared files remain pending.
  Future<PlatformFile> takePackage(
    IncomingSharedBatch batch,
    Map<Object?, Object?> source,
  ) async {
    if (_closed ||
        _submitted.contains(batch.id) ||
        batch.error != null ||
        !batch.notePackages.any((s) => s['lease'] == source['lease']) ||
        source['lease'] is! String) {
      throw StateError('This note package is no longer available.');
    }
    final claimed = await inbox.claim(batch.id, source['lease'] as String);
    PlatformFile file;
    try {
      if (_closed) throw StateError('The share owner has closed.');
      file = files.adoptDroppedSource(claimed);
    } catch (_) {
      const documents = MethodChannel('future_notes/documents');
      try {
        await documents.invokeMethod<void>('forgetPickedSource', {
          'identity': claimed['identity'],
        });
      } catch (_) {
        /* Close the live capability even if its grant expired. */
      }
      try {
        await documents.invokeMethod<void>('closePickedSource', {
          'lease': claimed['lease'],
        });
      } catch (_) {
        /* Native process teardown also closes its descriptors. */
      }
      await refreshInbox();
      rethrow;
    }
    await refreshInbox();
    return file;
  }

  @override
  Map<String, Object?>? recovery(String id) => _recoveries[id];
  @override
  Future<void> cancel(String id) async {
    final state = jobs.value
        .where((s) => s.progress.value.id == id)
        .firstOrNull;
    if (state == null || !state.progress.value.cancellable) return;
    _cancelled.add(id);
    _update(
      state,
      AttachmentJobPhase.cancelling,
      state.progress.value.bytes,
      state.progress.value.total,
    );
    await _transforms[id]?.cancel();
  }

  void _checkCredentials() {
    for (final id in _targets.keys.toList()) {
      if (!model.sharedTargetCredentialCurrent(_targets[id]!))
        unawaited(cancel(id));
    }
  }

  void _update(
    AttachmentJobState state,
    AttachmentJobPhase phase,
    int bytes,
    int? total, {
    String? detail,
    String? error,
  }) {
    final old = state.progress.value;
    if (!old.active) return;
    if (old.phase == AttachmentJobPhase.cancelling &&
        phase != AttachmentJobPhase.cancelled &&
        phase != AttachmentJobPhase.failed)
      return;
    state.update(
      AttachmentJobSnapshot(
        id: old.id,
        owner: old.owner,
        fileName: old.fileName,
        phase: phase,
        bytes: bytes,
        total: total,
        detail: detail,
        error: error,
        operation: AttachmentJobOperation.add,
        originalAttachmentId: old.id,
      ),
    );
  }

  Future<void> start(
    IncomingSharedBatch batch,
    SharedAttachmentTarget target,
  ) async {
    if (_closed || !_submitted.add(batch.id))
      throw StateError('This share has already been submitted.');
    final sources = <Map<Object?, Object?>>[];
    try {
      for (final source in batch.sources) {
        final file = files.adoptDroppedSource(source);
        if (file.path == null ||
            file.size > StreamingFileCipher.maxAttachmentBytes)
          throw StateError('Unsupported shared file.');
        sources.add(source);
      }
      if (sources.isEmpty)
        throw StateError(batch.error ?? 'No readable files were shared.');
      await inbox.acknowledge(batch.id);
      for (final source in sources) {
        final id = const Uuid().v4();
        final state = AttachmentJobState(
          AttachmentJobSnapshot(
            id: id,
            owner: -1,
            fileName: source['name'] as String,
            phase: AttachmentJobPhase.queued,
            total: source['length'] as int,
          ),
        );
        _targets[id] = target;
        _recoveries[id] = {
          'version': 1,
          'state': 'retryFromSource',
          'target': target.reference.fileName,
          'library': target.reference.binding.root,
          'fileName': source['name'],
          'attachment': id,
          'length': source['length'],
          'passwordRequired': target.password != null,
          'input': files.pickedSourceIdentity(source['path'] as String),
        };
        jobs.value = List.unmodifiable([...jobs.value, state]);
        final operation = _run(state, target, source);
        _running.add(operation);
        unawaited(operation.whenComplete(() => _running.remove(operation)));
      }
      await refreshInbox();
    } catch (_) {
      _submitted.remove(batch.id);
      for (final source in sources) {
        await files.releasePickedSource(source['path'] as String);
      }
      await inbox.discard(batch.id);
      await refreshInbox();
      rethrow;
    }
  }

  Future<void> _run(
    AttachmentJobState state,
    SharedAttachmentTarget target,
    Map<Object?, Object?> source,
  ) async {
    final id = state.progress.value.id;
    final path = source['path'] as String;
    final length = source['length'] as int;
    final policy = settings.attachmentPerformance;
    Directory? operation;
    var stage = 1;
    bool cancelled() =>
        _closed ||
        _cancelled.contains(id) ||
        !model.sharedTargetCredentialCurrent(target);
    try {
      if (cancelled()) throw const FileJobCancelled();
      await files.checkStagingCapacity(length);
      stage = 2;
      operation = await files.createOperationDirectory(target.reference);
      _recoveries[id]!['staging'] = operation.path
          .split(Platform.pathSeparator)
          .last;
      stage = 3;
      final output = await files.createAttachmentCandidate(
        target.reference,
        id,
        operation,
        length + 32,
      );
      stage = 4;
      final transform = worker.submit(
        FileTransformRequest(
          source: StreamingFileSource(path, length),
          destination: output.path,
          ownedTarget: output,
          decryptSource: false,
          encryptDestination: true,
          destinationPassword: target.password,
          verifyOutput: policy.verifyLargeFileWrites,
        ),
        onProgress: (phase, done, total) => _update(
          state,
          phase == 'Verifying'
              ? AttachmentJobPhase.verifying
              : AttachmentJobPhase.encrypting,
          done,
          total,
          detail: phase,
        ),
      );
      _transforms[id] = transform;
      if (cancelled()) await transform.cancel();
      final result = await transform.result;
      if (cancelled()) throw const FileJobCancelled();
      if (!result.isSuccess)
        throw StateError('Attachment encryption could not be completed.');
      _recoveries[id]!['plaintextHash'] = result.value!.plaintextHash;
      stage = 5;
      await model.commitSharedAttachment(
        target,
        AttachmentModel(
          id: id,
          fileName: state.progress.value.fileName,
          size: length,
          mimeType: 'application/octet-stream',
        ),
        PreparedAttachmentFile(
          id,
          StreamingFileSource(
            output.path,
            result.value!.length,
            receipt: result.value!.receipt,
          ),
          fileName: state.progress.value.fileName,
        ),
        cancelled: cancelled,
        onFinalizing: () => _update(
          state,
          AttachmentJobPhase.finalizing,
          length,
          length,
          detail: 'Saving encrypted file',
        ),
        onProgress: (phase, done, total) => _update(
          state,
          AttachmentJobPhase.finalizing,
          done,
          total,
          detail: phase,
        ),
      );
      _update(state, AttachmentJobPhase.completed, length, length);
    } on FileJobCancelled {
      _update(
        state,
        AttachmentJobPhase.cancelled,
        state.progress.value.bytes,
        length,
      );
    } catch (error) {
      MobileDiagnostics.record(MobileDiagnostic.jobRecordFailed, {
        'shared_stage': stage,
        'access': error is LibraryAccessException
            ? const [
                'not_folder',
                'name_exists',
                'stale_reference',
                'ambiguous_document',
                'conflict',
                'ioFailure',
                'recoveryRequired',
                'capacity_exceeded',
              ].indexOf(error.code)
            : -1,
        'state': error is StateError ? 1 : 0,
      });
      _update(
        state,
        AttachmentJobPhase.failed,
        state.progress.value.bytes,
        length,
        error:
            'This file could not be attached. Existing notes and completed attachments were retained.',
      );
    } finally {
      _transforms.remove(id);
      _targets.remove(id);
      if (operation != null) {
        try {
          await files.removeOperationDirectory(operation);
        } catch (_) {}
      }
      try {
        final phase = state.progress.value.phase;
        if (phase == AttachmentJobPhase.completed ||
            phase == AttachmentJobPhase.cancelled) {
          final identity = files.pickedSourceIdentity(path);
          if (identity != null) await files.forgetPickedSource(identity);
        }
        await files.releasePickedSource(path);
      } catch (_) {}
      jobs.value = List.unmodifiable(jobs.value);
    }
  }

  Future<void> close() async {
    for (final state in jobs.value) {
      await cancel(state.progress.value.id);
    }
    await Future.wait(_running.toList());
    await worker.close();
  }

  void dispose() {
    _closed = true;
    model.removeListener(_checkCredentials);
    inbox.dispose();
    // Orderly close joins work before this UI owner is disposed.
  }
}
