import 'package:flutter/material.dart';

class PasswordDialog extends StatefulWidget {
  final bool isUnlock;
  final Function(String) onConfirm;

  const PasswordDialog({
    super.key,
    this.isUnlock = false,
    required this.onConfirm,
  });

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscureText = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_passwordController.text.isNotEmpty) {
      widget.onConfirm(_passwordController.text);
      Navigator.pop(context);
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
        widget.isUnlock ? 'Unlock Note' : 'Set Password',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.isUnlock
                ? 'Enter password to unlock this note.'
                : 'This note will be encrypted using the password below.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscureText,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
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
                  _obscureText ? Icons.visibility : Icons.visibility_off,
                  color: Colors.blueAccent, // Matched with prefix icon
                ),
                tooltip: _obscureText ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
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
          child: Text(widget.isUnlock ? 'Unlock' : 'Set Password'),
        ),
      ],
    );
  }
}
