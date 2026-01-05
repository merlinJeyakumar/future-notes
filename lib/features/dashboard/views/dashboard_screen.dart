import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/sidebar.dart';
import '../widgets/content_area.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import '../widgets/import_confirmation_dialog.dart';

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
    // Assuming file.path is just filename (from getRecentFiles in ViewModel)
    // We need to reconstruct full path.
    // OR: Update ViewModel/Service to provide full path?
    // Current IMPL: recentFiles are filenames.
    // FileService puts them in UserData.

    // We can duplicate the path logic here or use a helper.
    // Replicating logic for expediency as FileService does hardcode 'UserData'.
    final directory = await getApplicationDocumentsDirectory();
    final fullPath = '${directory.path}/UserData/${file.path}';
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

  Future<void> _handleImport() async {
    final file = await _viewModel.pickImportFile();
    if (file != null) {
      // Show loading? Logic is fast enough usually.
      final verification = await _viewModel.verifyImportFile(file);

      if (!mounted) return;

      if (!verification.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verification.message),
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

      if (shouldImport == true) {
        await _viewModel.performImport(file);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("File imported successfully")),
          );
        }
      }
    }
  }

  void _showMasterSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text('About', style: TextStyle(color: Colors.white)),
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
              title: const Text('Theme', style: TextStyle(color: Colors.white)),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
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
                ),
          body: Row(
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
                ),

              Expanded(child: ContentArea(viewModel: _viewModel)),
            ],
          ),
        );
      },
    );
  }
}
