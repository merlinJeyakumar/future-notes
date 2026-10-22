import 'dart:convert';
import 'dart:io';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late String selected;
  late String previous;
  late File settings;
  late OwnedAppServices? app;
  late String original;
  setUp(() async {
    run = await createValidationRun();
    selected = p.join(run.path, 'selected');
    previous = p.join(run.path, 'previous-unavailable');
    settings = File(p.join(run.path, 'configuration', 'settings.json'));
    await settings.parent.create(recursive: true);
    original = jsonEncode({
      'customDataPath': previous,
      'unknown': {'keep': true},
    });
    await settings.writeAsString(original, flush: true);
    app = null;
  });
  tearDown(() async {
    if (app != null) expect((await app!.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });
  StorageEnvironment environment() => StorageEnvironment.recoverable(
    dataRoot: selected,
    settingsFile: settings.path,
  );

  test(
    'explicit startup selection is admitted before bookmark and setting acknowledgement',
    () async {
      var admitted = false;
      app = OwnedAppServices(
        environment: environment(),
        selectedLibraryOverride: selected,
        afterLibraryAdmission: () async {
          expect(
            await File(p.join(selected, '.future-notes-writer.lock')).exists(),
            isTrue,
          );
          expect(await settings.readAsString(), original);
          expect(await Directory(previous).exists(), isFalse);
          admitted = true;
        },
      );
      final result = await app!.initialize();
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(admitted, isTrue);
      expect(await app!.settings.getUserDataPath(), selected);
      final written = jsonDecode(await settings.readAsString());
      expect(written['customDataPath'], selected);
      expect(written['unknown'], {'keep': true});
      expect(await Directory(previous).exists(), isFalse);
    },
  );

  test(
    'a failed native bookmark acknowledgement preserves the original setting',
    () async {
      app = OwnedAppServices(
        environment: environment(),
        selectedLibraryOverride: selected,
        afterLibraryAdmission: () async {
          throw const FileSystemException('Synthetic denied bookmark write');
        },
      );
      expect((await app!.initialize()).isSuccess, isFalse);
      expect(app!.isReady, isFalse);
      expect(await settings.readAsString(), original);
      expect(await Directory(previous).exists(), isFalse);
    },
  );

  test('a raw override cannot broaden the captured storage capability', () {
    expect(
      () => OwnedAppServices(
        environment: environment(),
        selectedLibraryOverride: previous,
      ),
      throwsArgumentError,
    );
    expect(app, isNull);
  });
}
