import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/sidebar.dart';
import '../widgets/content_area.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import '../widgets/import_confirmation_dialog.dart';
import '../widgets/export_options_dialog.dart';
import '../services/settings_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ContentViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ContentViewModel(
      fileService: FileService(),
      encryptionService: EncryptionService(),
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleOpenFolder(RecentFile file) async {
    final fullPath = file.fullPath;
    final normalizedPath = fullPath.replaceAll(
      '/',
      '\\',
    ); // Windows consistency

    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', normalizedPath]);
    } else {
      // Fallback or other platforms
      print("Show in folder not implemented for this platform");
    }
  }

  void _handleDelete(RecentFile file) {
    _viewModel.deleteNote(file.path);
  }

  Future<void> _handleExportPack(RecentFile file) async {
    // Close the sidebar first on mobile
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // First load the note so we have access to attachments and metadata
    await _viewModel.loadNote(file.path);

    if (!mounted) return;

    // If note is locked, require password to export
    if (_viewModel.isLocked) {
      final unlocked = await _showUnlockForExportDialog();
      if (!unlocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot export: incorrect file password or cancelled',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // Show export options dialog
    final options = await showDialog<ExportOptions>(
      context: context,
      builder: (context) => ExportOptionsDialog(
        hasAttachments: _viewModel.attachments.isNotEmpty,
      ),
    );

    if (options == null) return;

    if (!mounted) return;

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Preparing export...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      // Export runs in background (uses compute internally)
      await _viewModel.exportNotePack(
        format: options.format,
        password: options.password,
      );

      if (!mounted) return;

      // Hide loading and show success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export ready! Share sheet will appear.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _showUnlockForExportDialog() async {
    final passwordController = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF161E2D),
          title: const Text(
            'Unlock to Export',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This note is password protected. Enter the password to export.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blueAccent),
                  ),
                  errorText: errorText,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                ),
                onSubmitted: (value) async {
                  final success = await _viewModel.unlockNote(value);
                  if (success) {
                    Navigator.pop(context, true);
                  } else {
                    setState(() => errorText = 'Incorrect password');
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final success = await _viewModel.unlockNote(
                  passwordController.text,
                );
                if (success) {
                  Navigator.pop(context, true);
                } else {
                  setState(() => errorText = 'Incorrect password');
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
    // Don't dispose controller here - it may still be referenced during rebuild
    // It will be garbage collected automatically
    return result ?? false;
  }

  Future<void> _handleImport() async {
    // Close the drawer first on mobile
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    final file = await _viewModel.pickImportPackFile();
    if (file == null) return;

    if (!mounted) return;

    // Verify the file
    final verification = await _viewModel.verifyImportFile(file);

    if (!mounted) return;

    if (!verification.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid file: ${verification.message}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) => ImportConfirmationDialog(
        fileName: file.name,
        fileType: verification.message,
        previewInfo: verification.previewInfo,
      ),
    );

    if (shouldImport != true) return;

    if (!mounted) return;

    String? importedNoteId;
    String? errorMessage;

    if (verification.isPack) {
      // Handle pack file import - always ask for optional archive password
      final password = await _showPackPasswordDialog(
        isRequired: verification.isPackEncrypted,
      );

      // If password is required and user cancelled, abort
      if (verification.isPackEncrypted && password == null) {
        return;
      }

      // Import runs in background (uses compute internally)
      importedNoteId = await _viewModel.importNotePack(
        file.path!,
        archivePassword: password,
      );

      if (importedNoteId == null) {
        // Determine error reason
        if (password != null && password.isNotEmpty) {
          errorMessage = 'Import failed - incorrect archive password';
        } else {
          errorMessage = 'Import failed - archive may be password protected';
        }
      }
    } else {
      // Handle regular file import
      await _viewModel.performImport(file);
      importedNoteId = 'success'; // placeholder for success check
    }

    if (!mounted) return;

    // Show result message
    if (importedNoteId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File imported successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Load the imported file if we have a real ID
      if (importedNoteId != 'success') {
        await _viewModel.loadNote(importedNoteId);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? 'Import failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _showPackPasswordDialog({bool isRequired = false}) async {
    final passwordController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161E2D),
        title: Text(
          isRequired ? 'Enter Archive Password' : 'Archive Password (Optional)',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isRequired
                  ? 'This archive is password protected. Enter the password to import.'
                  : 'If this archive has a password, enter it below. Leave empty if no password.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Archive Password',
                hintText: isRequired ? null : 'Leave empty if no password',
                hintStyle: const TextStyle(color: Colors.grey),
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          if (!isRequired)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Skip'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    // Don't dispose controller here - it will be garbage collected
    // If result is empty string (from Skip or empty input), treat as no password
    return result?.isEmpty == true ? null : result;
  }

  void _showMasterSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final settings = SettingsService();
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Settings',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // File Compression Setting
                ListTile(
                  leading: const Icon(Icons.compress, color: Colors.white70),
                  title: const Text(
                    'File Compression',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: DropdownButton<CompressionLevel>(
                    value: settings.compressionLevel,
                    dropdownColor: const Color(0xFF2D3748),
                    style: const TextStyle(color: Colors.white),
                    underline: Container(height: 1, color: Colors.blueAccent),
                    isExpanded: true,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: CompressionLevel.high,
                        child: Text("High (Max Compression)"),
                      ),
                      DropdownMenuItem(
                        value: CompressionLevel.medium,
                        child: Text("Medium (Half Size)"),
                      ),
                      DropdownMenuItem(
                        value: CompressionLevel.none,
                        child: Text("None (Full Size)"),
                      ),
                    ],
                    onChanged: (CompressionLevel? newValue) {
                      if (newValue != null) {
                        settings.setCompressionLevel(newValue).then((_) {
                          setState(() {});
                        });
                      }
                    },
                  ),
                ),
                if (!Platform.isAndroid && !Platform.isIOS) ...[
                  const Divider(color: Colors.grey),
                  ListTile(
                    leading: const Icon(
                      Icons.folder_open,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'App Data Folder',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: FutureBuilder<String>(
                      future: settings.getUserDataPath(),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? 'Loading...',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      onPressed: () async {
                        final String? selectedDirectory = await FilePicker
                            .platform
                            .getDirectoryPath();
                        if (selectedDirectory != null) {
                          await settings.setCustomDataPath(selectedDirectory);
                          setState(() {});
                          _viewModel.loadRecentFiles();
                        }
                      },
                    ),
                  ),
                ],
                const Divider(color: Colors.grey),
                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'About',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'AntiGravity Notes v1.0',
                    style: TextStyle(color: Colors.grey),
                  ),
                  onTap: () {},
                ),
                ListTile(
                  leading: const Icon(
                    Icons.color_lens_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Theme',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Dark Mode',
                    style: TextStyle(color: Colors.grey),
                  ),
                  onTap: () {},
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
            SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                _viewModel.saveNote(),
            SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
                _viewModel.reset(),
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 800;
              return Scaffold(
                resizeToAvoidBottomInset: false,
                backgroundColor: const Color(0xFF1B2535),
                appBar: isDesktop
                    ? null
                    : AppBar(
                        backgroundColor: const Color(0xFF161E2D),
                        title: const Text('Dashboard'),
                        iconTheme: const IconThemeData(color: Colors.white),
                        titleTextStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.settings),
                            onPressed: () => _showMasterSettings(context),
                          ),
                        ],
                      ),
                drawer: isDesktop
                    ? null
                    : Sidebar(
                        recentFiles: _viewModel.recentFiles,
                        onFileSelected: (path) {
                          _viewModel.loadNote(path);
                          Navigator.pop(context); // Close drawer
                        },
                        onOpenFolder: _handleOpenFolder,
                        onDelete: _handleDelete,
                        onNewNote: () {
                          _viewModel.reset();
                          Navigator.pop(context);
                        },
                        onImportNote: _handleImport,
                        onSettings: () {
                          Navigator.pop(context);
                          _showMasterSettings(context);
                        },
                        onRefresh: _viewModel.loadRecentFiles,
                        onSearchChanged: _viewModel.setSearchQuery,
                        onExportPack: (file) {
                          Navigator.pop(context);
                          _handleExportPack(file);
                        },
                      ),
                body: Stack(
                  children: [
                    Row(
                      children: [
                        if (isDesktop)
                          Sidebar(
                            recentFiles: _viewModel.recentFiles,
                            onFileSelected: (path) => _viewModel.loadNote(path),
                            onOpenFolder: _handleOpenFolder,
                            onDelete: _handleDelete,
                            onNewNote: _viewModel.reset,
                            onImportNote: _handleImport,
                            onSettings: () => _showMasterSettings(context),
                            onRefresh: _viewModel.loadRecentFiles,
                            onSearchChanged: _viewModel.setSearchQuery,
                            onExportPack: _handleExportPack,
                          ),
                        Expanded(child: ContentArea(viewModel: _viewModel)),
                      ],
                    ),
                    if (_viewModel.isBusy)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.blueAccent,
                              ),
                              SizedBox(height: 16),
                              Text(
                                "Processing...",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
