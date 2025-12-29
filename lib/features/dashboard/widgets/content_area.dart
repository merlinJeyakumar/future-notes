import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../viewmodels/content_viewmodel.dart';

class ContentArea extends StatefulWidget {
  final ContentViewModel viewModel;

  const ContentArea({super.key, required this.viewModel});

  @override
  State<ContentArea> createState() => _ContentAreaState();
}

class _ContentAreaState extends State<ContentArea>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging ||
        _tabController.index != widget.viewModel.activeTabIndex) {
      widget.viewModel.setActiveTab(_tabController.index);
      setState(() {}); // Rebuild to update toolbar
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen width to decide layout if needed, though now unified.
    // final isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      color: const Color(0xFF1B2535),
      child: Column(
        children: [
          // Toolbar - Row 1: Title & Primary Action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1B2535),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.viewModel.titleController,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter Message Title',
                      hintStyle: TextStyle(color: Colors.white30),
                      border: InputBorder.none,
                      prefixText: 'Editing: ',
                      prefixStyle: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                if (widget.viewModel.isPasswordSet) ...[
                  OutlinedButton.icon(
                    onPressed: () => widget.viewModel.manualLock(),
                    icon: const Icon(
                      Icons.lock,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                    label: const Text(
                      "Lock",
                      style: TextStyle(color: Colors.blueAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blueAccent),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12, // Match height of ElevatedButton
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  // Call viewModel.saveNote directly
                  onPressed: widget.viewModel.isBusy
                      ? null
                      : () => widget.viewModel.saveNote(),
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
                  child: widget.viewModel.isBusy
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

          // Toolbar - Row 2: Tabs & Tools
          Container(
            color: const Color(0xFF0F172A),
            child: Column(
              children: [
                // Top Tab Bar
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Editor'),
                    Tab(text: 'Text'),
                  ],
                  labelColor: Colors.blueAccent,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blueAccent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: const Color(0xFF334155),
                ),
                // Tool buttons / Quill Toolbar
                if (!widget.viewModel.isLocked) ...[
                  if (_tabController.index == 0) ...[
                    Container(
                      color: const Color(
                        0xFF1B2535,
                      ), // Dark background to match app theme
                      width: double.infinity,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          iconTheme: const IconThemeData(color: Colors.white70),
                          canvasColor: const Color(0xFF1B2535),
                        ),
                        child: quill.QuillSimpleToolbar(
                          controller: widget.viewModel.quillController,
                          config: const quill.QuillSimpleToolbarConfig(),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Markdown tools (reused existing logic essentially, or simplified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF334155)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildToolbarIcon(
                            Icons.attach_file,
                            'Attach File',
                            onPressed: widget.viewModel.pickFile,
                          ),
                          const SizedBox(width: 8),
                          _buildToolbarIcon(
                            widget.viewModel.isLocked
                                ? Icons.lock
                                : (widget.viewModel.isPasswordSet
                                      ? Icons.lock
                                      : Icons.lock_outline),
                            widget.viewModel.isLocked
                                ? 'Unlock Note'
                                : (widget.viewModel.isPasswordSet
                                      ? 'Remove Password'
                                      : 'Set Password'),
                            onPressed: () {
                              if (widget.viewModel.isLocked) {
                                _showPasswordDialog(context, isUnlock: true);
                              } else if (widget.viewModel.isPasswordSet) {
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
                                          widget.viewModel.clearPassword();
                                          Navigator.pop(context);
                                        },
                                        child: const Text(
                                          'Remove',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                _showPasswordDialog(context);
                              }
                            },
                            color:
                                (widget.viewModel.isLocked ||
                                    widget.viewModel.isPasswordSet)
                                ? Colors.blueAccent
                                : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Editor Area
          Expanded(
            child: widget.viewModel.isLocked
                ? _buildLockedView(context)
                : TabBarView(
                    controller: _tabController,
                    physics:
                        const NeverScrollableScrollPhysics(), // Disable swipe to avoid conflict with editor
                    children: [
                      _buildRichEditor(context),
                      _buildMarkdownEditor(context),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichEditor(BuildContext context) {
    return Container(
      color: const Color(0xFF1B2535), // Dark background to match app theme
      padding: const EdgeInsets.all(16),
      child: Theme(
        data: ThemeData.dark().copyWith(
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white),
          ),
        ),
        child: quill.QuillEditor.basic(
          controller: widget.viewModel.quillController,
          config: quill.QuillEditorConfig(
            placeholder: 'Start writing...',
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownEditor(BuildContext context) {
    return Container(
      color: const Color(0xFF1B2535),
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: widget.viewModel.textController,
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
        onChanged: widget.viewModel.onTextChanged,
      ),
    );
  }

  Widget _buildLockedView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            "This note is locked.",
            style: TextStyle(color: Colors.grey, fontSize: 18),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showPasswordDialog(context, isUnlock: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("Unlock"),
          ),
        ],
      ),
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

  Future<void> _showPasswordDialog(
    BuildContext context, {
    bool isUnlock = false,
  }) async {
    final passwordController = TextEditingController();
    bool obscureText = true;

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              Navigator.pop(context);
              if (passwordController.text.isNotEmpty) {
                if (isUnlock) {
                  widget.viewModel.unlockNote(passwordController.text);
                } else {
                  widget.viewModel.setPassword(passwordController.text);
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Text(
                isUnlock ? 'Unlock Note' : 'Set Password',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUnlock
                        ? 'Enter password to unlock this note.'
                        : 'This note will be encrypted using the password below.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscureText,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.blueAccent),
                      hintText: 'Enter password',
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
                  onPressed: submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(isUnlock ? 'Unlock' : 'Set Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
