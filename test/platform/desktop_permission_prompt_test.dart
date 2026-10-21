import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/macos_file_access.dart';
import 'package:flutter_application_1/core/storage/desktop_storage_bootstrap.dart';
import 'package:flutter_application_1/core/storage/desktop_storage_startup.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/mac-permission-prompt');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Widget prompt({String code = 'permission_required'}) => DesktopStorageStartup(
    environment: const StorageEnvironment.production(),
    fileAccess: const MacosFileAccess(channel: channel),
    resolvePlan: (_) async =>
        throw DesktopLibraryAccessRequired('/opaque/synthetic', code: code),
    buildReady: (_, _, _) => const SizedBox(),
  );

  testWidgets(
    'missing access never prompts automatically and chooser cancellation remains usable',
    (tester) async {
      var requests = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        requests++;
        return null;
      });
      await tester.pumpWidget(prompt());
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.text('Choose notes folder'), findsOneWidget);
      await tester.pump(const Duration(minutes: 3));
      expect(requests, 0);
      await tester.tap(find.text('Choose notes folder'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Choose notes folder'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native denial is actionable and no path or raw error is displayed',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'access_denied',
          message: '/sensitive/native/path',
        );
      });
      await tester.pumpWidget(prompt());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose notes folder'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Folder access was denied. Choose your notes folder to allow access.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('/sensitive'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('a missing entitlement is distinguished from user denial', (
    tester,
  ) async {
    await tester.pumpWidget(prompt(code: 'entitlement_missing'));
    await tester.pumpAndSettle();
    expect(
      find.text('This build is missing its signed macOS file permissions.'),
      findsOneWidget,
    );
    expect(find.textContaining('/opaque'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
