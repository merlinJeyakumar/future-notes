import 'package:flutter/material.dart';

enum PasswordMode { unlock, set, update }

class PasswordDialog extends StatefulWidget {
  final PasswordMode mode;
  final Function(String) onConfirm;
  final Future<bool> Function(String)? onVerifyCurrent;

  const PasswordDialog({
    super.key,
    this.mode = PasswordMode.unlock,
    required this.onConfirm,
    this.onVerifyCurrent,
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      title: Text(
        _title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _description,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),

            // Current Password Field (Update Mode Only)
            if (widget.mode == PasswordMode.update)
              _buildTextField(
                controller: _currentController,
                label: 'Current Password',
                autofocus: true,
              ),

            if (widget.mode == PasswordMode.update) const SizedBox(height: 12),

            // New Password Field (All Modes - acts as "Enter Password" for Unlock)
            _buildTextField(
              controller: _passwordController,
              label: widget.mode == PasswordMode.unlock
                  ? 'Password'
                  : 'New Password',
              autofocus:
                  widget.mode !=
                  PasswordMode.update, // Autofocus if first field
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
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isVerifying ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
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
    return TextField(
      controller: controller,
      obscureText: _obscureText,
      autofocus: autofocus,
      enabled: !_isVerifying,
      textInputAction: isLast || widget.mode == PasswordMode.unlock
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.blueAccent),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
        ),
        prefixIcon: const Icon(Icons.lock_outline, color: Colors.blueAccent),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
            color: Colors.blueAccent,
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
