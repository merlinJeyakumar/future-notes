import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum PasswordMode { unlock, set, update }

class PasswordDialog extends StatefulWidget {
  final PasswordMode mode;
  final Function(String) onConfirm;
  final Future<bool> Function(String)? onVerifyCurrent;
  final String? title;
  final String? description;

  const PasswordDialog({
    super.key,
    this.mode = PasswordMode.unlock,
    required this.onConfirm,
    this.onVerifyCurrent,
    this.title,
    this.description,
  });

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureText = true;
  bool _isVerifying = false;
  String? _errorText;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorText = null;
      _isVerifying = true;
    });

    try {
      // Mode specific validation
      if (widget.mode == PasswordMode.update) {
        if (widget.onVerifyCurrent != null) {
          final isValid = await widget.onVerifyCurrent!(
            _currentController.text,
          );
          if (!mounted) return;
          if (!isValid) {
            setState(() {
              _errorText = "Incorrect current password";
              _isVerifying = false;
            });
            return;
          }
        }
      } else if (widget.mode == PasswordMode.unlock) {
        if (widget.onVerifyCurrent != null) {
          final isValid = await widget.onVerifyCurrent!(
            _passwordController.text,
          );
          if (!mounted) return;
          if (!isValid) {
            setState(() {
              _errorText = "Incorrect password";
              _isVerifying = false;
            });
            return;
          }
        }
      }

      if (widget.mode == PasswordMode.set ||
          widget.mode == PasswordMode.update) {
        if (_passwordController.text.length < 4) {
          setState(() {
            _errorText = "Password must be at least 4 characters";
            _isVerifying = false;
          });
          return;
        }
        if (_passwordController.text != _confirmController.text) {
          setState(() {
            _errorText = "Passwords do not match";
            _isVerifying = false;
          });
          return;
        }
      }

      // Success
      final result = _passwordController.text;

      if (result.isNotEmpty) {
        widget.onConfirm(result);
        if (mounted) Navigator.pop(context, result);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  String get _title {
    if (widget.title != null) return widget.title!;
    switch (widget.mode) {
      case PasswordMode.unlock:
        return 'Unlock Note';
      case PasswordMode.set:
        return 'Set Password';
      case PasswordMode.update:
        return 'Update Password';
    }
  }

  String get _description {
    if (widget.description != null) return widget.description!;
    switch (widget.mode) {
      case PasswordMode.unlock:
        return 'Enter password to unlock this note.';
      case PasswordMode.set:
        return 'Enter a new password to protect this note.';
      case PasswordMode.update:
        return 'Enter your current password and a new password.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.appBorder),
      ),
      title: Text(
        _title,
        style: TextStyle(
          color: theme.appTextPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _description,
              style: TextStyle(color: theme.appTextSecondary, fontSize: 11.232),
            ),
            const SizedBox(height: 16),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorText!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11.232,
                  ),
                ),
              ),

            // Current Password Field (Update Mode Only)
            if (widget.mode == PasswordMode.update)
              _buildTextField(
                controller: _currentController,
                label: 'Current Password',
              ),

            if (widget.mode == PasswordMode.update) const SizedBox(height: 12),

            // New Password Field (All Modes - acts as "Enter Password" for Unlock)
            _buildTextField(
              controller: _passwordController,
              label: widget.mode == PasswordMode.unlock
                  ? 'Password'
                  : 'New Password',
            ),

            if (widget.mode != PasswordMode.unlock) ...[
              const SizedBox(height: 12),
              // Confirm Password Field (Set/Update Modes)
              _buildTextField(
                controller: _confirmController,
                label: 'Confirm Password',
                isLast: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isVerifying ? null : () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: theme.appTextSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _isVerifying ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isVerifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.mode == PasswordMode.unlock ? 'Unlock' : 'Save'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool autofocus = false,
    bool isLast = false,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: _obscureText,
      autofocus: autofocus,
      enabled: !_isVerifying,
      textInputAction: isLast || widget.mode == PasswordMode.unlock
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: (_) => _submit(),
      style: TextStyle(color: theme.appTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.colorScheme.primary),
        filled: true,
        fillColor: theme.appBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        prefixIcon: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
            color: theme.colorScheme.primary,
          ),
          tooltip: _obscureText ? 'Show password' : 'Hide password',
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
        ),
      ),
    );
  }
}
