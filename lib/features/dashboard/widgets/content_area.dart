import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';

class ContentArea extends StatefulWidget {
  const ContentArea({super.key});

  @override
  State<ContentArea> createState() => _ContentAreaState();
}

class _ContentAreaState extends State<ContentArea> {
  // Dependency Injection could also happen in main.dart or a provider
  final ContentViewModel _viewModel = ContentViewModel(
    fileService: FileService(),
    encryptionService: EncryptionService(),
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
              // Toolbar - Row 1: Title & Primary Action
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: const Color(0xFF1B2535),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Editing: Deployment Plan',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      // Call _viewModel.saveNote directly
                      onPressed: _viewModel.isBusy
                          ? null
                          : () => _viewModel.saveNote(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        elevation: 0,
                      ),
                      child: _viewModel.isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Note',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),

              // Toolbar - Row 2: Tools
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildToolbarIcon(
                      Icons.attach_file,
                      'Attach File',
                      onPressed: _viewModel.pickFile,
                    ),
                    const SizedBox(width: 8),
                    _buildToolbarIcon(
                      _viewModel.isPasswordSet
                          ? Icons.lock
                          : Icons.lock_outline,
                      _viewModel.isPasswordSet
                          ? 'Remove Password'
                          : 'Set Password',
                      onPressed: () {
                        if (_viewModel.isPasswordSet) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1E293B),
                              title: const Text(
                                'Remove Password?',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: const Text(
                                'Are you sure you want to remove the password protection?',
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _viewModel.clearPassword();
                                    Navigator.pop(context);
                                  },
                                  child: const Text(
                                    'Remove',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else {
                          _showPasswordDialog(context);
                        }
                      },
                      color: _viewModel.isPasswordSet
                          ? Colors.blueAccent
                          : Colors.grey,
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
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: color ?? Colors.grey, size: 20),
      tooltip: tooltip,
      constraints: const BoxConstraints(), // Compact constraints
      padding: const EdgeInsets.all(8), // Consistent padding
      splashRadius: 20,
    );
  }

  Future<void> _showPasswordDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    bool obscureText = true;

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: const Text(
                'Enter Password',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This note will be encrypted using the password below.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscureText,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.blueAccent),
                      hintText: 'Enter secure password',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.blueAccent,
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Colors.blueAccent,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            obscureText = !obscureText;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (passwordController.text.isNotEmpty) {
                      _viewModel.setPassword(passwordController.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Set Password'),
                ),
              ],
            );
          },
        );
      },
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
        softLineBreak: true,
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
