import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../services/settings_service.dart';
import '../views/mobile_library_startup.dart';
import 'mobile_theme.dart';
import '../../../core/platform/mobile_diagnostics.dart';
import '../../../core/platform/android_native_cipher.dart';
import '../../../core/platform/mobile_export.dart';
import 'dart:async';

/// No desktop frame, density adjustment or desktop theme mutation lives here.
class MobileApp extends StatefulWidget {
  const MobileApp({super.key, required this.settings});
  final SettingsService settings;
  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> with WidgetsBindingObserver {
  (int, int)? _lastSize;
  bool _metricsScheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      MobileExport.initialize().catchError((Object _) {
        MobileDiagnostics.record(MobileDiagnostic.jobChannelFailed, {
          'stage': 3,
        });
      }),
    );
    didChangeMetrics();
    widget.settings.themeModeNotifier.addListener(_changed);
    widget.settings.attachmentPerformanceNotifier.addListener(
      _performanceChanged,
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _performanceChanged() {
    unawaited(
      AndroidNativeCipher.configure(
        widget.settings.attachmentPerformance,
      ).catchError((Object _) {
        MobileDiagnostics.record(MobileDiagnostic.jobChannelFailed, {
          'stage': 2,
        });
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.themeModeNotifier.removeListener(_changed);
    widget.settings.attachmentPerformanceNotifier.removeListener(
      _performanceChanged,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    MobileDiagnostics.record(MobileDiagnostic.lifecycle, {
      'state': state.index,
    });
  }

  @override
  void didChangeMetrics() {
    if (_metricsScheduled) return;
    _metricsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsScheduled = false;
      if (!mounted) return;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final view = views.first;
      final size = (
        view.physicalSize.width.round(),
        view.physicalSize.height.round(),
      );
      if (size == _lastSize) return;
      _lastSize = size;
      MobileDiagnostics.record(MobileDiagnostic.metrics, {
        'width_px': size.$1,
        'height_px': size.$2,
        'ratio': view.devicePixelRatio,
      });
    });
  }

  @override
  void didHaveMemoryPressure() {
    // PaintingBinding already releases unused decoded images. Keep active
    // editors, viewers and disk-backed decrypted cache ownership unchanged.
    MobileDiagnostics.record(MobileDiagnostic.memoryPressure, {
      'image_bytes': PaintingBinding.instance.imageCache.currentSizeBytes,
      'image_count': PaintingBinding.instance.imageCache.currentSize,
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Future Notes Preview',
    debugShowCheckedModeBanner: false,
    theme: MobileTheme.light,
    darkTheme: MobileTheme.dark,
    themeMode: widget.settings.themeMode,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: FlutterQuillLocalizations.supportedLocales,
    builder: (context, child) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
          systemNavigationBarIconBrightness: dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: MobileLibraryStartup(settings: widget.settings),
  );
}
