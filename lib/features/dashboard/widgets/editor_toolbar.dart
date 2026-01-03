import 'package:flutter/material.dart';

class EditorToolbar extends StatelessWidget {
  final bool isLocked;
  final bool isPasswordSet;
  final VoidCallback onPickFile;
  final VoidCallback onLockPressed;
  final VoidCallback onTerminalPressed;
  final VoidCallback onSettingsPressed;

  const EditorToolbar({
    super.key,
    required this.isLocked,
    required this.isPasswordSet,
    required this.onPickFile,
    required this.onLockPressed,
    required this.onTerminalPressed,
    required this.onSettingsPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isLocked) ...[
            _buildToolbarIcon(
              Icons.attach_file,
              'Attach File',
              onPressed: onPickFile,
            ),
            const SizedBox(width: 8),
          ],
          _buildToolbarIcon(
            isLocked
                ? Icons.lock
                : (isPasswordSet ? Icons.lock : Icons.lock_outline),
            isLocked
                ? 'Unlock Note'
                : (isPasswordSet ? 'Remove Password' : 'Set Password'),
            onPressed: onLockPressed,
            color: (isLocked || isPasswordSet)
                ? Colors.blueAccent
                : Colors.grey,
          ),
          _buildToolbarIcon(
            Icons.terminal,
            'Terminal',
            onPressed: onTerminalPressed,
          ),
          const SizedBox(width: 8),
          _buildToolbarIcon(
            Icons.settings_outlined,
            'Settings',
            onPressed: onSettingsPressed,
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
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(8),
      splashRadius: 20,
    );
  }
}
