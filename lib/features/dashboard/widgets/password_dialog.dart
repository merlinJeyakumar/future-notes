import 'package:flutter/material.dart';

enum PasswordMode { unlock, set, update }

class PasswordDialog extends StatefulWidget {
  final PasswordMode mode;
  final Function(String) onConfirm;
  final bool Function(String)? onVerifyCurrent;

  const PasswordDialog({
    super.key,
    this.mode = PasswordMode.unlock,
    required this.onConfirm,
    this.onVerifyCurrent,
  });

  // Backward compatibility constructor if needed, or simply update calls
  // We will update calls in ContentArea, so standard constructor is fine.

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureText = true;
  String? _errorText;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _errorText = null);

    // Mode specific validation
    if (widget.mode == PasswordMode.update) {
      if (widget.onVerifyCurrent != null) {
        if (!widget.onVerifyCurrent!(_currentController.text)) {
          setState(() => _errorText = "Incorrect current password");
          return;
        }
      }
    }

    if (widget.mode == PasswordMode.set || widget.mode == PasswordMode.update) {
      if (_passwordController.text.length < 4) {
        setState(() => _errorText = "Password must be at least 4 characters");
        return;
      }
      if (_passwordController.text != _confirmController.text) {
        setState(() => _errorText = "Passwords do not match");
        return;
      }
    }

    // Success
    final result = widget.mode == PasswordMode.unlock
        ? _passwordController.text
        : _passwordController.text;

    if (result.isNotEmpty) {
      widget.onConfirm(result);
      Navigator.pop(context, result);
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(widget.mode == PasswordMode.unlock ? 'Unlock' : 'Save'),
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
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onSubmitted: isLast ? (_) => _submit() : null,
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
