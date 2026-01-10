import 'package:flutter/material.dart';
import '../services/pack_service.dart';

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
    return AlertDialog(
      backgroundColor: const Color(0xFF161E2D),
      title: const Text(
        'Export Options',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Format',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
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
            const Divider(color: Colors.grey),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text(
                'Password Protection',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Encrypt the export with a password',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              value: _usePassword,
              onChanged: (value) {
                setState(() {
                  _usePassword = value;
                  _passwordError = null;
                });
              },
              activeColor: Colors.blueAccent,
              contentPadding: EdgeInsets.zero,
            ),
            if (_usePassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
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
                ),
                onChanged: (_) => setState(() => _passwordError = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
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
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blueAccent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This note has attachments. They will be included in the export.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
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
          child: const Text('Cancel'),
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
    final isSelected = _selectedFormat == format;
    return InkWell(
      onTap: () => setState(() => _selectedFormat = format),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : const Color(0xFF334155),
          ),
        ),
        child: Row(
          children: [
            Radio<ExportFormat>(
              value: format,
              groupValue: _selectedFormat,
              onChanged: (value) => setState(() => _selectedFormat = value!),
              activeColor: Colors.blueAccent,
            ),
            Icon(icon, color: Colors.white70, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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
