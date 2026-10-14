import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'owned_app_services.dart';

/// Owns failed startup resources; never falls back to the direct writer.
class StorageStartupFailure extends StatefulWidget {
  const StorageStartupFailure({super.key, this.services});

  final OwnedAppServices? services;

  @override
  State<StorageStartupFailure> createState() => _StorageStartupFailureState();
}

class _StorageStartupFailureState extends State<StorageStartupFailure> {
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
          'Storage startup failed. No library was opened for editing.\n'
          'Check storage configuration, permissions and recovery before retrying.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
