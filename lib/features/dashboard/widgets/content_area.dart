import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';

class ContentArea extends StatefulWidget {
  const ContentArea({super.key});

  @override
  State<ContentArea> createState() => _ContentAreaState();
}

class _ContentAreaState extends State<ContentArea> {
  // Dependency Injection could also happen in main.dart or a provider
  final ContentViewModel _viewModel = ContentViewModel(
    fileService: FileService(),
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen width to decide layout
    final isDesktop = MediaQuery.of(context).size.width > 900;

    // ListenableBuilder rebuilds whenever the viewModel notifies listeners
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        return Container(
          color: const Color(0xFF1B2535),
          child: Column(
            children: [
              // Toolbar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Editing: Deployment Plan',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save Note',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildToolbarIcon(
                      Icons.attach_file,
                      'Attach File',
                      onPressed: _viewModel.pickFile,
                    ),
                    const SizedBox(width: 8),
                    _buildToolbarIcon(
                      Icons.lock_outline,
                      'Password',
                      onPressed: () {},
                    ),
                    _buildToolbarIcon(
                      Icons.terminal,
                      'Terminal',
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    _buildToolbarIcon(
                      Icons.settings_outlined,
                      'Settings',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              // Editor Area
              Expanded(
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildInputArea()),
                          const VerticalDivider(
                            width: 1,
                            color: Color(0xFF334155),
                          ),
                          Expanded(child: _buildPreviewArea()),
                        ],
                      )
                    : DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            const TabBar(
                              tabs: [
                                Tab(text: 'Edit'),
                                Tab(text: 'Preview'),
                              ],
                              labelColor: Colors.blueAccent,
                              unselectedLabelColor: Colors.grey,
                              indicatorColor: Colors.blueAccent,
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _buildInputArea(),
                                  _buildPreviewArea(),
                                ],
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
    );
  }

  Widget _buildToolbarIcon(
    IconData icon,
    String tooltip, {
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.grey, size: 20),
      tooltip: tooltip,
      constraints: const BoxConstraints(), // Compact constraints
      padding: const EdgeInsets.all(8), // Consistent padding
      splashRadius: 20,
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _viewModel.textController,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Type markdown here...',
          hintStyle: TextStyle(color: Colors.grey),
        ),
        onChanged: _viewModel.onTextChanged,
      ),
    );
  }

  Widget _buildPreviewArea() {
    int checkboxIndex = 0;

    return Container(
      color: const Color(0xFF0F172A), // Slightly darker for preview
      child: Markdown(
        data: _viewModel.textController.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(color: Colors.white70, fontSize: 16),
          h1: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
          h2: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
          code: const TextStyle(
            backgroundColor: Color(0xFF1E293B),
            color: Colors.greenAccent,
            fontFamily: 'monospace',
          ),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
          ),
          checkbox: const TextStyle(color: Colors.blueAccent),
        ),
        checkboxBuilder: (bool value) {
          final currentIndex = checkboxIndex++;
          return GestureDetector(
            onTap: () {
              _viewModel.toggleCheckbox(currentIndex);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                color: value ? Colors.blueAccent : Colors.grey,
                size: 20,
              ),
            ),
          );
        },
      ),
    );
  }
}
