import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/operations/operation_result.dart';
import '../services/settings_service.dart';

class AppSettingsDialog extends StatefulWidget {
  const AppSettingsDialog({
    super.key,
    required this.settings,
    required this.pickLibrary,
    required this.openLibrary,
    this.loadVersion,
  });
  final SettingsService settings;
  final Future<String?> Function() pickLibrary;
  final Future<OperationResult<void>> Function(String) openLibrary;
  final Future<String> Function()? loadVersion;
  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late Future<String> _libraryPath;
  late final Future<String> _version;
  final _pending = <String>{};
  String? _error;
  @override
  void initState() {
    super.initState();
    _libraryPath = widget.settings.getUserDataPath();
    _version = widget.loadVersion?.call() ?? _loadVersion();
  }

  Future<String> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    return 'Future Notes ${info.version}${info.buildNumber.isEmpty ? '' : '+${info.buildNumber}'}';
  }

  Future<void> _write(String key, Future<void> Function() action) async {
    if (!_pending.add(key)) return;
    setState(() => _error = null);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Settings could not be saved. The previous value was retained.',
        );
      }
    } finally {
      _pending.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openLibrary() => _write('library', () async {
    final directory = await widget.pickLibrary();
    if (!mounted || directory == null) return;
    final result = await widget.openLibrary(directory);
    if (!mounted) return;
    // The acknowledged settings location is authoritative even when a switch
    // reports a retained late edit or deferred old-library cleanup.
    _libraryPath = widget.settings.getUserDataPath();
    if (!result.isSuccess) {
      _error = result.message ?? 'The library could not be opened.';
    }
  });

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return AlertDialog(
      title: const Text('App settings'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              title: Text('Closing the app'),
              subtitle: Text(
                'Close asks for confirmation, then exits Future Notes.',
              ),
            ),
            ListTile(
              title: const Text('Theme'),
              subtitle: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                isExpanded: true,
                items: ThemeMode.values
                    .map(
                      (mode) =>
                          DropdownMenuItem(value: mode, child: Text(mode.name)),
                    )
                    .toList(),
                onChanged: _pending.contains('theme')
                    ? null
                    : (value) {
                        if (value != null) {
                          _write('theme', () => settings.setThemeMode(value));
                        }
                      },
              ),
            ),
            ListTile(
              title: const Text('File compression'),
              subtitle: DropdownButton<CompressionLevel>(
                value: settings.compressionLevel,
                isExpanded: true,
                items: CompressionLevel.values
                    .map(
                      (level) => DropdownMenuItem(
                        value: level,
                        child: Text(level.name),
                      ),
                    )
                    .toList(),
                onChanged: _pending.contains('compression')
                    ? null
                    : (value) {
                        if (value != null) {
                          _write(
                            'compression',
                            () => settings.setCompressionLevel(value),
                          );
                        }
                      },
              ),
            ),
            if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) ...[
              const Divider(),
              const Text(
                'Current library',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              FutureBuilder<String>(
                future: _libraryPath,
                builder: (context, snapshot) => SelectableText(
                  snapshot.hasError
                      ? 'Library location unavailable'
                      : snapshot.data ?? 'Loading…',
                ),
              ),
              TextButton.icon(
                onPressed: _pending.contains('library') ? null : _openLibrary,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _pending.contains('library')
                      ? 'Opening library…'
                      : 'Open another library',
                ),
              ),
            ],
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(),
            const Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
            FutureBuilder<String>(
              future: _version,
              builder: (context, snapshot) => Text(
                snapshot.hasError
                    ? 'Future Notes · version unavailable'
                    : snapshot.data ?? 'Future Notes',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
