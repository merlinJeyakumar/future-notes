import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'core/storage/storage_environment.dart';
import 'core/storage/validation_app_services.dart';
import 'features/dashboard/services/settings_service.dart';
import 'features/dashboard/views/dashboard_screen.dart';
import 'main.dart' show MyApp;

/// Separate executable target: missing validation defines never fall back to
/// Documents/UserData, and the normal main.dart does not activate this writer.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ValidationAppServices? services;
  try {
    final environment = StorageEnvironment.fromDefines();
    if (!environment.isValidation) {
      throw StateError('Explicit isolation required.');
    }
    // Older read-only helpers still consult the singleton. Configure it before
    // any initialization so even those helpers cannot resolve production data.
    SettingsService().configureStorage(environment);
    final runtime = ValidationAppServices(environment: environment);
    services = runtime;
    final initialized = await runtime.initialize();
    if (initialized.isSuccess) {
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
  } catch (_) {
    // Never expose paths, keys, payloads, or raw native errors on startup.
  }
  await services?.close();
  runApp(_StartupFailure(services: services));
}

class _StartupFailure extends StatefulWidget {
  const _StartupFailure({this.services});
  final ValidationAppServices? services;

  @override
  State<_StartupFailure> createState() => _StartupFailureState();
}

class _StartupFailureState extends State<_StartupFailure> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        final closed = await widget.services?.close();
        return closed == null || closed.isSuccess
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text(
          'Validation startup failed. No library was opened for editing.\n'
          'Check the isolated configuration before trying again.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
