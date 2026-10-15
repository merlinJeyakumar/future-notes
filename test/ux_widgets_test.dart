import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/theme/app_theme.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_list_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/widgets/app_settings_dialog.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_presentation.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';
import 'support/editor_harness.dart';

class _FailingSettings extends SettingsService {
  _FailingSettings()
    : super.withStorage(
        storage: StorageEnvironment.validation(
          validationRoot: 'D:/future-notes-validation-ui',
          dataRoot: 'D:/future-notes-validation-ui/library',
          settingsFile: 'D:/future-notes-validation-ui/config/settings.json',
        ),
      );
  int paths = 0;
  final write = Completer<void>();
  @override
  Future<String> getUserDataPath() async {
    paths++;
    return 'D:/synthetic-library';
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) => write.future;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('compact UI typography preserves document sizes / dark=$dark', (
      tester,
    ) async {
      final raw = dark ? ThemeData.dark() : ThemeData.light();
      final base = ThemeData.localize(raw, raw.typography.englishLike);
      final compact = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      expect(
        compact.textTheme.bodyMedium!.fontSize,
        closeTo(base.textTheme.bodyMedium!.fontSize! * .7776, .01),
      );
      expect(
        compact.textTheme.labelLarge!.fontSize,
        lessThan(base.textTheme.labelLarge!.fontSize!),
      );
      late DefaultStyles styles;
      await tester.pumpWidget(
        MaterialApp(
          theme: compact,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                styles = DefaultStyles.getInstance(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(styles.paragraph!.style.fontSize, 16);
      expect(styles.h1!.style.fontSize, 34);
      expect(styles.h2!.style.fontSize, 30);
    });
  }

  for (final width in [360.0, 800.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('editor controls reflow at $width / $scale / dark=$dark', (
          tester,
        ) async {
          final h = await EditorHarness.create(
            deltaToHtml: (_) async => '<p>body</p>',
          );
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          try {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: const [
                  FlutterQuillLocalizations.delegate,
                ],
                supportedLocales: FlutterQuillLocalizations.supportedLocales,
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1100),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(body: ContentArea(viewModel: h.editor)),
                ),
              ),
            );
            expect(find.text('Save Note'), findsOneWidget);
            expect(find.text('Unsaved draft'), findsNothing);
            final save = find.widgetWithText(ElevatedButton, 'Save Note');
            expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
            expect(tester.getRect(save).right, closeTo(width - 20, .1));
            expect(find.byType(TextField), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            h.disposeEditor();
            await tester.pump(const Duration(seconds: 3));
            await tester.runAsync(h.dispose);
          }
        });
      }
    }
  }

  testWidgets(
    'Save follows real draft changes without a separate status label',
    (tester) async {
      final h = await EditorHarness.create();
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            supportedLocales: FlutterQuillLocalizations.supportedLocales,
            home: Scaffold(body: ContentArea(viewModel: h.editor)),
          ),
        );
        ElevatedButton save() =>
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(save().onPressed, isNull);
        h.editor.titleController.text = 'Synthetic note';
        await tester.pump();
        expect(save().onPressed, isNotNull);
        final pause = PausePoint();
        h.encryption.nextAppEncryption = pause;
        final saving = h.editor.saveNote();
        await pause.started.future;
        await tester.pump();
        expect(save().onPressed, isNull);
        expect(find.widgetWithText(ElevatedButton, 'Saving…'), findsOneWidget);
        pause.resume();
        expect((await saving).isSuccess, isTrue);
        await tester.pump();
        expect(save().onPressed, isNull);
        expect(find.text('Saved'), findsNothing);
        expect(find.text('Unsaved changes'), findsNothing);
        h.editor.titleController.text = 'Changed synthetic note';
        await tester.pump();
        expect(save().onPressed, isNotNull);
        h.files.failWrites = true;
        expect((await h.editor.saveNote()).isSuccess, isFalse);
        await tester.pump();
        expect(
          find.widgetWithText(ElevatedButton, 'Retry Save'),
          findsOneWidget,
        );
        expect(save().onPressed, isNotNull);
        expect(find.text('Save failed'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'sidebar keeps controlled query through remount and clears it explicitly',
    (tester) async {
      final controller = TextEditingController(text: 'synthetic query');
      final focus = FocusNode();
      String? changed;
      Widget sidebar(String query) => MaterialApp(
        home: Scaffold(
          body: Sidebar(
            key: ValueKey(query),
            listState: NoteListUiState(query: query),
            searchController: controller,
            searchFocusNode: focus,
            onSearchChanged: (q) => changed = q,
            onFileSelected: (_) {},
            onOpenFolder: (_) {},
            onDelete: (_) {},
            onNewNote: () {},
          ),
        ),
      );
      await tester.pumpWidget(sidebar(controller.text));
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pumpWidget(sidebar('replacement'));
      expect(controller.text, 'synthetic query');
      expect(controller.selection.baseOffset, 4);
      await tester.tap(find.byTooltip('Clear search'));
      expect(controller.text, isEmpty);
      expect(changed, '');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
    },
  );

  testWidgets(
    'settings retain acknowledged values on failure and cache metadata futures',
    (tester) async {
      final settings = _FailingSettings();
      var versions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSettingsDialog(
              settings: settings,
              pickLibrary: () async => null,
              openLibrary: (_) async => const OperationResult.success(),
              loadVersion: () async {
                versions++;
                return 'Future Notes synthetic-version';
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final old = settings.themeMode;
      tester
          .widget<DropdownButton<ThemeMode>>(
            find.byType(DropdownButton<ThemeMode>),
          )
          .onChanged!(ThemeMode.dark);
      await tester.pump();
      expect(
        tester
            .widget<DropdownButton<ThemeMode>>(
              find.byType(DropdownButton<ThemeMode>),
            )
            .onChanged,
        isNull,
      );
      settings.write.completeError(StateError('synthetic failure'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, old);
      expect(
        find.textContaining('previous value was retained'),
        findsOneWidget,
      );
      expect(settings.paths, 1);
      expect(versions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.themeModeNotifier.dispose();
    },
  );

  testWidgets('viewer fallback offers a guarded direct system action', (
    tester,
  ) async {
    final done = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentPreviewFallback(
            message: 'Synthetic unavailable preview',
            onOpenSystem: () {
              calls++;
              return done.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open in system app'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Opening…'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open in system app'), findsOneWidget);
  });

  test(
    'phase-only updates and large sizes are independent from byte ticks',
    () {
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'x',
          owner: 0,
          fileName: 'video.avi',
          phase: AttachmentJobPhase.encrypting,
        ),
      );
      var phases = 0;
      job.phase.addListener(() => phases++);
      job.update(
        const AttachmentJobSnapshot(
          id: 'x',
          owner: 0,
          fileName: 'video.avi',
          phase: AttachmentJobPhase.encrypting,
          bytes: 100,
        ),
      );
      expect(phases, 0);
      job.update(
        const AttachmentJobSnapshot(
          id: 'x',
          owner: 0,
          fileName: 'video.avi',
          phase: AttachmentJobPhase.cancelling,
          bytes: 100,
        ),
      );
      expect(phases, 1);
      expect(job.progress.value.active, isTrue);
      expect(job.progress.value.cancellable, isFalse);
      expect(formatAttachmentBytes(0), '0 B');
      expect(formatAttachmentBytes(10 * 1024 * 1024 * 1024), '10.0 GiB');
      for (final name in ['video.avi', 'video.mkv', 'video.mp4', 'video.mov']) {
        expect(attachmentVisualKind(name), AttachmentVisualKind.video);
      }
      job.dispose();
    },
  );

  test(
    'normal text and primary button text meet contrast targets in both themes',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(
          contrast(theme.appTextSecondary, theme.appBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(theme.appSubtleGray, theme.appSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );
}
