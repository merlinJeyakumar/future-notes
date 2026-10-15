import 'package:flutter/material.dart';
import '../services/pack_service.dart';
import '../../../core/theme/app_theme.dart';

/// Dialog result containing export options
class ExportOptions {
  final ExportFormat format;
  final String? password;

  ExportOptions({required this.format, this.password});
}

/// Dialog for selecting export format and optional password
class ExportOptionsDialog extends StatefulWidget {
  final bool hasAttachments;

  const ExportOptionsDialog({super.key, required this.hasAttachments});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ExportFormat _selectedFormat = ExportFormat.binary;
  bool _usePassword = false;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _passwordError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _export() {
    if (_usePassword) {
      if (_passwordController.text.isEmpty) {
        setState(() => _passwordError = 'Password cannot be empty');
        return;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        setState(() => _passwordError = 'Passwords do not match');
        return;
      }
      if (_passwordController.text.length < 4) {
        setState(
          () => _passwordError = 'Password must be at least 4 characters',
        );
        return;
      }
    }

    Navigator.pop(
      context,
      ExportOptions(
        format: _selectedFormat,
        password: _usePassword ? _passwordController.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.appSurface,
      title: Text(
        'Export Options',
        style: TextStyle(color: theme.appTextPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Format',
              style: TextStyle(
                color: theme.appSubtleGray,
                fontSize: 10.368,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildFormatOption(
              format: ExportFormat.binary,
              title: 'Binary Pack (.fnote)',
              subtitle: 'Compact format, smaller file size',
              icon: Icons.archive,
            ),
            const SizedBox(height: 8),
            _buildFormatOption(
              format: ExportFormat.zip,
              title: 'ZIP Archive (.zip)',
              subtitle: 'Standard format, can be opened with any ZIP tool',
              icon: Icons.folder_zip,
            ),
            const SizedBox(height: 20),
            Divider(color: theme.appDivider),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(
                'Password Protection',
                style: TextStyle(color: theme.appTextPrimary),
              ),
              subtitle: Text(
                'Encrypt the export with a password',
                style: TextStyle(color: theme.appSubtleGray, fontSize: 10.368),
              ),
              value: _usePassword,
              onChanged: (value) {
                setState(() {
                  _usePassword = value;
                  _passwordError = null;
                });
              },
              activeColor: theme.colorScheme.primary,
              contentPadding: EdgeInsets.zero,
            ),
            if (_usePassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                autofocus: true,
                obscureText: true,
                style: TextStyle(color: theme.appTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: theme.appSubtleGray),
                  filled: true,
                  fillColor: theme.appBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.appBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.appBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
                onChanged: (_) => setState(() => _passwordError = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                style: TextStyle(color: theme.appTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: TextStyle(color: theme.appSubtleGray),
                  filled: true,
                  fillColor: theme.appBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.appBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.appBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  errorText: _passwordError,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                ),
                onChanged: (_) => setState(() => _passwordError = null),
              ),
            ],
            if (widget.hasAttachments) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This note has attachments. They will be included in the export.',
                        style: TextStyle(
                          color: theme.appTextSecondary,
                          fontSize: 10.368,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: theme.appTextSecondary),
          ),
        ),
        FilledButton(onPressed: _export, child: const Text('Export')),
      ],
    );
  }

  Widget _buildFormatOption({
    required ExportFormat format,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedFormat == format;
    return InkWell(
      onTap: () => setState(() => _selectedFormat = format),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.15)
              : theme.appBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.appBorder,
          ),
        ),
        child: Row(
          children: [
            Radio<ExportFormat>(
              value: format,
              groupValue: _selectedFormat,
              onChanged: (value) => setState(() => _selectedFormat = value!),
              activeColor: theme.colorScheme.primary,
            ),
            Icon(icon, color: theme.appTextSecondary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.appTextPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.appSubtleGray,
                      fontSize: 10.368,
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
}
