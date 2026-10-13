import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/dashboard/views/dashboard_screen.dart';
import 'features/dashboard/services/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/storage_environment.dart';
import 'core/storage/owned_app_services.dart';
import 'core/storage/storage_startup_failure.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OwnedAppServices? services;
  try {
    final environment = StorageEnvironment.fromDefines();
    SettingsService().configureStorage(environment);
    if (environment.hasOwnedStorage) {
      final runtime = OwnedAppServices(environment: environment);
      services = runtime;
      final initialized = await runtime.initialize();
      if (!initialized.isSuccess) {
        runApp(StorageStartupFailure(services: runtime));
        return;
      }
      runApp(
        MyApp(
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
    runApp(const MyApp());
  } catch (_) {
    // A bad opt-in configuration must never select the old writer as fallback.
    runApp(StorageStartupFailure(services: services));
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.settings, this.home});

  final SettingsService? settings;
  final Widget? home;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final _settings = widget.settings ?? SettingsService();

  @override
  void initState() {
    super.initState();
    _settings.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _settings.themeModeNotifier.removeListener(_onThemeChanged);
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
