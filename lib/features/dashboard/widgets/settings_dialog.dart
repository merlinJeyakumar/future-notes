import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/settings_service.dart';

class SettingsDialog extends StatefulWidget {
  final VoidCallback? onRefresh;

  const SettingsDialog({super.key, this.onRefresh});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final SettingsService _settings = SettingsService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // Constrain width for desktop, full width for mobile
    final double dialogWidth = size.width > 600 ? 500 : size.width * 0.9;
    final double dialogHeight = size.height * 0.8;

    return Dialog(
      backgroundColor: Colors.transparent, // Use container for styling
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: dialogHeight),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(theme),
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),

            // Body - Scrollable to prevent overflow
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _buildThemeSection(theme),
                    _buildDivider(theme),
                    _buildCompressionSection(theme),
                    _buildDivider(theme),
                    _buildEditorSection(theme),
                    _buildDivider(theme),
                    _buildStorageSection(theme),
                    _buildDivider(theme),
                    _buildAboutSection(theme),
                  ],
                ),
              ),
            ),

            // Footer (optional, could be actions)
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.settings_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'Settings',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      color: theme.dividerColor.withOpacity(0.1),
      indent: 24,
      endIndent: 24,
      height: 1,
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary.withOpacity(0.8),
          ),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary.withOpacity(0.8),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Appearance', Icons.palette_outlined),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          title: const Text('Theme Mode'),
          subtitle: const Text('Choose your preferred look'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ThemeMode>(
                value: _settings.themeMode,
                isDense: true,
                dropdownColor: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    _settings.setThemeMode(mode).then((_) {
                      if (mounted) setState(() {});
                    });
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompressionSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Storage', Icons.sd_storage_outlined),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          title: const Text('Image Compression'),
          subtitle: const Text('Quality vs Size trade-off'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CompressionLevel>(
                value: _settings.compressionLevel,
                isDense: true,
                dropdownColor: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem(
                    value: CompressionLevel.high,
                    child: Text('High'),
                  ),
                  DropdownMenuItem(
                    value: CompressionLevel.medium,
                    child: Text('Medium'),
                  ),
                  DropdownMenuItem(
                    value: CompressionLevel.none,
                    child: Text('None'),
                  ),
                ],
                onChanged: (level) {
                  if (level != null) {
                    _settings.setCompressionLevel(level).then((_) {
                      if (mounted) setState(() {});
                    });
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Editor', Icons.edit_note_rounded),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          title: const Text('Auto Save'),
          subtitle: const Text('Save automatically after 2s'),
          value: _settings.autoSave,
          activeColor: theme.colorScheme.primary,
          onChanged: (value) async {
            await _settings.setAutoSave(value);
            if (mounted) setState(() {});
          },
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          title: const Text('Collapse on Edit'),
          subtitle: const Text('Hide attachments when editing'),
          value: _settings.autoCollapseAttachments,
          activeColor: theme.colorScheme.primary,
          onChanged: (value) async {
            await _settings.setAutoCollapseAttachments(value);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildStorageSection(ThemeData theme) {
    if (Platform.isAndroid || Platform.isIOS) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Data Location', Icons.folder_open_rounded),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          title: const Text('Data Folder'),
          subtitle: FutureBuilder<String>(
            future: _settings.getUserDataPath(),
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? 'Default',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontFamily: 'monospace',
                ),
              );
            },
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final String? selectedDirectory = await FilePicker.platform
                  .getDirectoryPath();
              if (selectedDirectory != null) {
                await _settings.setCustomDataPath(selectedDirectory);
                if (mounted) setState(() {});
                widget.onRefresh?.call();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'About', Icons.info_outline_rounded),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          title: const Text('Future Notes'),
          subtitle: const Text('v1.0.0 • Secure, Privacy-first Notes'),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.rocket_launch_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
