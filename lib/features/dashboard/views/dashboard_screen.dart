import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../widgets/content_area.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';

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

  @override
  Widget build(BuildContext context) {
    // Basic responsive check
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF1B2535),
          // On mobile, show an AppBar to open the drawer
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
                ),
          drawer: isDesktop
              ? null
              : Sidebar(
                  recentFiles: _viewModel.recentFiles,
                  onFileSelected: (file) {
                    _viewModel.loadNote(file);
                    Navigator.pop(context); // Close drawer
                  },
                ),
          body: Row(
            children: [
              // On Desktop, show Sidebar permanently
              if (isDesktop)
                Sidebar(
                  recentFiles: _viewModel.recentFiles,
                  onFileSelected: (file) => _viewModel.loadNote(file),
                ),

              // Main Content Area
              Expanded(child: ContentArea(viewModel: _viewModel)),
            ],
          ),
        );
      },
    );
  }
}
