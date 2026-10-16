import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/dashboard/views/dashboard_screen.dart';
import 'features/dashboard/services/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/motion_frame_log.dart';
import 'core/storage/storage_environment.dart';
import 'core/storage/owned_app_services.dart';
import 'core/storage/storage_startup_failure.dart';
import 'core/storage/windows_storage_bootstrap.dart';
import 'core/platform/windows_navigation_shortcuts.dart';
import 'core/platform/window_actions.dart';
import 'features/dashboard/widgets/desktop_window_frame.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OwnedAppServices? services;
  try {
    var environment = StorageEnvironment.fromDefines();
    if (!kIsWeb && Platform.isWindows && !environment.hasOwnedStorage) {
      environment = await WindowsStorageBootstrap.resolve();
    }
    SettingsService().configureStorage(environment);
    if (environment.hasOwnedStorage) {
      final runtime = OwnedAppServices(environment: environment);
      services = runtime;
      final initialized = await runtime.initialize();
      if (!initialized.isSuccess) {
        if (kDebugMode)
          debugPrint(
            'Future Notes startup failed (${initialized.outcome.name}).',
          );
        runApp(StorageStartupFailure(services: runtime));
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'Future Notes startup: owned storage ready; canonical main editor selected.',
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) =>
              debugPrint('Future Notes startup: first editor frame delivered.'),
        );
      }
      runApp(
        MyApp(
          windowActions: !kIsWeb && Platform.isWindows
              ? WindowsWindowActions()
              : null,
          settings: runtime.settings,
          home: DashboardScreen(
            settings: runtime.settings,
            fileService: runtime.files,
            onClose: runtime.close,
          ),
        ),
      );
      return;
    }
    await SettingsService().init();
    runApp(
      MyApp(
        windowActions: !kIsWeb && Platform.isWindows
            ? WindowsWindowActions()
            : null,
      ),
    );
  } catch (_) {
    if (kDebugMode)
      debugPrint(
        'Future Notes startup failed (configuration or storage admission).',
      );
    // A bad opt-in configuration must never select the old writer as fallback.
    runApp(StorageStartupFailure(services: services));
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.settings, this.home, this.windowActions});

  final SettingsService? settings;
  final Widget? home;
  final WindowActions? windowActions;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final _settings = widget.settings ?? SettingsService();
  MotionFrameLog? _motionFrameLog;

  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('FN_MOTION_DIAGNOSTICS')) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      _motionFrameLog = MotionFrameLog(
        refreshRate: views.isEmpty ? 60 : views.first.display.refreshRate,
      )..start();
    }
    _settings.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _motionFrameLog?.stop();
    _settings.themeModeNotifier.removeListener(_onThemeChanged);
    unawaited(widget.windowActions?.dispose());
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
    _updateSystemUI();
  }

  void _updateSystemUI() {
    final isDark =
        _settings.themeMode == ThemeMode.dark ||
        (_settings.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Update system UI on build
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateSystemUI());

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Future Notes',
      builder: (context, child) => WindowsNavigationShortcuts(
        child: widget.windowActions == null
            ? child ?? const SizedBox.shrink()
            : DesktopWindowFrame(
                actions: widget.windowActions!,
                child: child ?? const SizedBox.shrink(),
              ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _settings.themeMode,
      home: widget.home ?? const DashboardScreen(),
    );
  }
}
