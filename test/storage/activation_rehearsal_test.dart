import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/note_envelope.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/note_codec.dart';

// This rehearsal is deliberately opt-in. Never infer Documents or settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final selected = Platform.environment['FN_REHEARSAL_ROOT'];
  test(
    'verified copy supports compatible commits and interruption recovery',
    () async {
      var phase = 'admission';
      OwnedAppServices? services;
      RecoverableStore? store;
      try {
        final root = p.normalize(selected!);
        final required = p.join(
          Directory.current.path,
          '.validation',
          p.basename(root),
        );
        if (!Platform.isWindows ||
            !p.isAbsolute(root) ||
            !p.equals(root, required) ||
            !RegExp(r'^future-notes-validation-activation-rehearsal-[A-Za-z0-9-]+$').hasMatch(p.basename(root))) {
          throw StateError('Rehearsal admission failed.');
        }
        final library = p.join(root, 'library');
        final validation = StorageEnvironment.validation(
          validationRoot: root,
          dataRoot: library,
          settingsFile: p.join(root, 'configuration', 'settings.json'),
        );
        await validation.verifyConfiguredPaths();
        final admission =
            jsonDecode(
                  await File(p.join(root, 'admission.json')).readAsString(),
                )
                as Map<String, dynamic>;
        if (admission['version'] != 1 || admission['backupVerified'] != true) {
          throw StateError('Verified copy receipt is required.');
        }
        final inventory = admission['inventory'] as List;
        phase = 'copy hash verification';
        for (final raw in inventory) {
          final entry = raw as Map<String, dynamic>;
          final target = p.normalize(
            p.join(library, entry['relative'] as String),
          );
          if (!p.isWithin(library, target)) {
            throw StateError('Escaped entry.');
          }
          await validation.verifyLocation(target);
          if (entry['directory'] == true) {
            continue;
          }
          final file = File(target);
          if (await file.length() != entry['length'] ||
              (await sha256.bind(file.openRead()).first)
                      .toString()
                      .toUpperCase() !=
                  entry['sha256']) {
            throw StateError('Copy verification failed.');
          }
        }
        phase = 'shared-root worker startup';
        services = OwnedAppServices(
          environment: StorageEnvironment.recoverable(
            dataRoot: library,
            settingsFile: p.join(library, 'settings.json'),
          ),
        );
        if (!(await services.initialize()).isSuccess) {
          throw StateError('Copied library startup failed.');
        }
        final objects = (await services.files.getRecentFiles())
            .where((name) => name.startsWith('note_'))
            .toList();
        if (objects.isEmpty) {
          throw StateError('No copied notes were admitted.');
        }
        final candidates = <String, String>{};
        final primitives = NativeStoragePrimitives(validation);
        phase = 'compatible reads and acknowledged worker commits';
        for (final name in objects) {
          final reference = await services.files.resolveNote(name);
          if (reference == null) {
            throw StateError('Missing copied note.');
          }
          final content = await services.files.readResolved(reference);
          if (content == null) {
            throw StateError('Unreadable copied note.');
          }
          final decoded = await NoteCodec.decode(
            content,
            decryptApp: EncryptionService().decryptAppResult,
          );
          for (final attachment in decoded.note.attachments) {
            final object = p.normalize(
              p.join(
                reference.withModelId(decoded.note.id).attachmentLocation,
                '${attachment.id}.med',
              ),
            );
            if (!p.isWithin(library, object)) {
              throw StateError('Escaped attachment.');
            }
            await validation.verifyLocation(object);
            if (await FileSystemEntity.type(object, followLinks: false) !=
                FileSystemEntityType.file) {
              throw StateError('A declared copied attachment is missing.');
            }
          }
          final before = await primitives.captureRevision(
            reference.contentPath,
          );
          final acknowledged = await services.files.writeResolved(
            reference,
            content,
          );
          final after = await primitives.captureRevision(reference.contentPath);
          if (before.sha256Hex != after.sha256Hex ||
              acknowledged.storageRevision?.sha256Hex != after.sha256Hex) {
            throw StateError('Compatible commit did not preserve exact bytes.');
          }
          // Change only the title on the copy; preserve protected body, unknown
          // metadata and the envelope kind. Original library is never admitted.
          final metadata = Map<String, dynamic>.from(decoded.metadata);
          metadata['title'] = 'Synthetic recovery rehearsal';
          final json = jsonEncode(metadata);
          candidates[p.posix.joinAll(
            p.split(p.relative(reference.contentPath, from: library)),
          )] = decoded.kind == NoteEnvelopeKind.appEncrypted
              ? await EncryptionService().encryptApp(json)
              : json;
        }
        if (!(await services.close()).isSuccess) {
          throw StateError('Worker cleanup failed.');
        }
        services = null;

        for (final note in candidates.entries) {
          final file = File(p.joinAll([library, ...p.posix.split(note.key)]));
          final source = File(p.join(root, 'sources', 'candidate'));
          await source.parent.create(recursive: true);
          await source.writeAsString(note.value, flush: true);
          for (final boundary in [
            CommitBoundary.previousMoved,
            CommitBoundary.published,
          ]) {
            phase = 'interruption rehearsal ${boundary.name}';
            final expected = await primitives.captureRevision(file.path);
            final opened = await RecoverableStore.open(
              root: library,
              environment: validation,
              faultHook: (point, _) async {
                if (point == boundary) {
                  throw StateError('Synthetic interruption');
                }
              },
            );
            if (!opened.isSuccess) {
              throw StateError('Copy owner startup failed.');
            }
            store = opened.value!;
            final failed = await store.commit(
              target: note.key,
              expected: expected,
              source: CommitFileSource(source.path, await source.length()),
            );
            if (failed.isSuccess) {
              throw StateError('Interrupted commit was acknowledged.');
            }
            await store.close();
            store = null;
            final recovered = await RecoverableStore.open(
              root: library,
              environment: validation,
            );
            if (!recovered.isSuccess) {
              throw StateError('Copy recovery startup failed.');
            }
            store = recovered.value!;
            final actual = await primitives.captureRevision(file.path);
            if (actual.sha256Hex != expected.sha256Hex ||
                store.recovery.libraryReadOnly ||
                store.recovery.blockedTargets.isNotEmpty ||
                store.recovery.restoredTransactions == 0) {
              throw StateError('Prior copied version was not recovered.');
            }
            await store.close();
            store = null;
          }
        }
        phase = 'reopen compatibility';
        services = OwnedAppServices(
          environment: StorageEnvironment.recoverable(
            dataRoot: library,
            settingsFile: p.join(library, 'settings.json'),
          ),
        );
        if (!(await services.initialize()).isSuccess) {
          throw StateError('Reopen failed.');
        }
        if (!(await services.close()).isSuccess) {
          throw StateError('Final cleanup failed.');
        }
        services = null;
        await File(p.join(root, 'rehearsal-result.json')).writeAsString(
          jsonEncode({
            'version': 1,
            'complete': true,
            'notes': objects.length,
            'interruptionChecks': candidates.length * 2,
            'completedUtc': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true,
        );
      } catch (_) {
        // Flutter's test reporter must never print note text, IDs or paths.
        fail('Isolated activation rehearsal failed during $phase.');
      } finally {
        if (store != null) {
          await store.close();
        }
        if (services != null) {
          if (!(await services.close()).isSuccess) {
            fail('Copied owner cleanup failed.');
          }
        }
      }
    },
    skip: selected == null
        ? 'Requires an explicitly verified disposable copy.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
