import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import '../support/validation_directory.dart';

void main() {
  test(
    'desktop 1.4.1 reader refuses an interrupted provider library and accepts clean handoff',
    () async {
      final run = await Directory.systemTemp.createTemp(
        'future-notes-validation-provider-guard-',
      );
      RecoverableStore? owner;
      try {
        final root = p.join(run.path, 'library');
        final environment = StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: root,
          settingsFile: p.join(run.path, 'config', 'settings.json'),
        );
        final guard = File(
          p.join(
            root,
            '.future-notes-storage',
            'transactions',
            '00000000-0000-4000-8000-000000000001.json',
          ),
        );
        await guard.parent.create(recursive: true);
        await guard.writeAsString(
          '{"version":2,"id":"00000000-0000-4000-8000-000000000001","intent":{"length":5,"sha256":"${'a' * 64}"}}',
          flush: true,
        );
        final canonical = File(p.join(root, 'synthetic.enc'));
        await canonical.writeAsString('Synthetic canonical bytes', flush: true);
        final opened = await RecoverableStore.open(
          root: root,
          environment: environment,
        );
        expect(opened.isSuccess, isTrue);
        owner = opened.value!;
        expect(owner.recovery.libraryReadOnly, isTrue);
        expect(await canonical.readAsString(), 'Synthetic canonical bytes');
        await owner.close();
        owner = null;
        // Simulate the provider coordinator's final acknowledged guard removal.
        await guard.delete();
        final clean = await RecoverableStore.open(
          root: root,
          environment: environment,
        );
        expect(clean.isSuccess, isTrue);
        owner = clean.value!;
        expect(owner.recovery.libraryReadOnly, isFalse);
        expect(await canonical.readAsString(), 'Synthetic canonical bytes');
      } finally {
        await owner?.close();
        await deleteValidationRun(run);
      }
    },
    skip: !Platform.isWindows,
  );
}
