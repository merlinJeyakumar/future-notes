import 'package:flutter/material.dart';

/// An editor-owned form; changing notes disposes its password and pending UI.
class NoteUnlockForm extends StatefulWidget {
  const NoteUnlockForm({
    super.key,
    required this.focusNode,
    required this.onUnlock,
  });

  final FocusNode focusNode;
  final Future<bool> Function(String password) onUnlock;

  @override
  State<NoteUnlockForm> createState() => _NoteUnlockFormState();
}

class _NoteUnlockFormState extends State<NoteUnlockForm> {
  final _password = TextEditingController();
  bool _working = false;
  bool _obscured = true;
  String? _error;

  Future<void> _unlock() async {
    if (_working) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      widget.focusNode.requestFocus();
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    bool unlocked;
    try {
      unlocked = await widget.onUnlock(_password.text);
    } catch (_) {
      unlocked = false;
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      if (unlocked) {
        _password.clear();
      } else {
        _error = 'Could not unlock. Check your password and try again.';
        _password.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _password.text.length,
        );
      }
    });
    if (!unlocked) widget.focusNode.requestFocus();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'This note is locked',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('note-unlock-password'),
                controller: _password,
                focusNode: widget.focusNode,
                autofocus: true,
                obscureText: _obscured,
                readOnly: _working,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _unlock(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    onPressed: _working
                        ? null
                        : () {
                            setState(() => _obscured = !_obscured);
                            widget.focusNode.requestFocus();
                          },
                    icon: Icon(
                      _obscured ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _working ? null : _unlock,
                child: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
