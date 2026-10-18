import 'package:flutter/material.dart';

/// Shared placement and icon for application-level task access on every layout.
class AppOverflowMenu extends StatelessWidget {
  const AppOverflowMenu({super.key, required this.onBackgroundTasks});
  final VoidCallback onBackgroundTasks;
  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    tooltip: 'More actions',
    icon: const Icon(Icons.more_vert),
    onSelected: (_) => onBackgroundTasks(),
    itemBuilder: (_) => const [
      PopupMenuItem(value: true, child: BackgroundTasksActionLabel()),
    ],
  );
}

class BackgroundTasksActionLabel extends StatelessWidget {
  const BackgroundTasksActionLabel({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.pending_actions, size: 20),
      SizedBox(width: 12),
      Flexible(child: Text('Background tasks')),
    ],
  );
}
