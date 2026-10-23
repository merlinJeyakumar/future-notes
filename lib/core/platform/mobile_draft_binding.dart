import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/dashboard/viewmodels/content_viewmodel.dart';
import '../../features/dashboard/widgets/password_dialog.dart';
import '../theme/app_dialog.dart';
import '../operations/operation_result.dart';
import 'mobile_diagnostics.dart';

class MobileDraftBinding with WidgetsBindingObserver {
  MobileDraftBinding({
    required this.model,
    required this.library,
    required this.context,
    required this.onRecovered,
  }) {
    WidgetsBinding.instance.addObserver(this);
    model.addListener(_changed);
    model.quillController.addListener(_changed);
    model.htmlController.addListener(_changed);
    model.titleController.addListener(_changed);
    model.saveStateNotifier.addListener(_changed);
    restored = _restore();
  }
  static const _channel = MethodChannel('future_notes/private_drafts');
  final ContentViewModel model;
  final String library;
  final BuildContext Function() context;
  final VoidCallback onRecovered;
  late final Future<void> restored;
  Timer? _timer;
  bool _closed = false;
  bool _ready = false;
  bool _writing = false;
  bool _again = false;
  int _epoch = 0;
  Completer<void>? _writeDone;
  Object? _observedDraft;
  Object? _flushedDraft;

  Object get _draftIdentity => (
    model.draftSession.generation,
    model.draftSession.editRevision,
    model.draftSession.persistedRevision,
    model.draftSession.credentialGeneration,
    model.draftSession.access,
    model.editorMode,
  );

  Future<T?> _dialog<T>(
    BuildContext ctx,
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    final navigator = Navigator.of(ctx, rootNavigator: true);
    final route = AppDialogRoute<T>(
      context: ctx,
      builder: builder,
      themes: InheritedTheme.capture(from: ctx, to: navigator.context),
      barrierDismissible: barrierDismissible,
    );
    final result = await navigator.push(route);
    // The next prompt must not overlap the previous route's dismissal.
    await route.completed;
    return result;
  }

  Future<void> _restore() async {
    try {
      final encoded = await _channel.invokeMethod<String>('read', {
        'library': library,
      });
      if (encoded != null) {
        final draft = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        if (!_closed) {
          final ctx = context();
          if (!ctx.mounted) return;
          final recover = await _dialog<bool>(
            ctx,
            (dialog) => AlertDialog(
              title: const Text('Recover unsaved draft?'),
              content: const Text(
                'A private recovery copy is available. Recovering a new draft does not save it to the library.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Discard'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Recover'),
                ),
              ],
            ),
            barrierDismissible: false,
          );
          if (_closed) return;
          if (recover == false) {
            await clear();
          } else if (recover == true) {
            String? password;
            if (draft['protected'] == true) {
              final passwordContext = context();
              if (!passwordContext.mounted) return;
              password = await _dialog<String>(
                passwordContext,
                (_) => PasswordDialog(
                  title: 'Unlock recovery draft',
                  preventDuplicateSubmissions: true,
                  onConfirm: (_) {},
                  onVerifyCurrent: (value) => _closed
                      ? Future.value(false)
                      : model.verifyPrivateRecoveryPassword(draft, value),
                ),
              );
              // Cancel leaves recovery encrypted and available next startup.
              if (_closed || password == null) return;
            }
            final result = await model.recoverPrivateDraft(
              draft,
              password: password,
            );
            if (_closed) return;
            if (result.isSuccess) {
              MobileDiagnostics.record(MobileDiagnostic.draftRecovered);
              onRecovered();
            } else {
              final errorContext = context();
              if (!errorContext.mounted) return;
              await _dialog<void>(
                errorContext,
                (dialog) => AlertDialog(
                  title: const Text('Recovery retained'),
                  content: Text(
                    result.message ?? 'Recovery could not be applied.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              );
              // A retained conflict is not permission to prompt again or
              // replace the unresolved journal with the current editor.
              return;
            }
          } else {
            // System Back dismisses presentation; only Discard deletes a draft.
            return;
          }
        }
      }
      if (_closed) return;
      _ready = true;
      _changed();
    } catch (_) {
      MobileDiagnostics.record(MobileDiagnostic.draftReadFailed);
      // Do not overwrite material whose authenticated decryption failed.
      _ready = false;
      if (!_closed)
        model.operationResultNotifier.value = const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Private draft recovery is unavailable. The previous recovery copy was retained; new edits cannot replace it.',
        );
    }
  }

  void _changed() {
    if (_closed || !_ready) return;
    final identity = _draftIdentity;
    if (_observedDraft == identity) return;
    _observedDraft = identity;
    _epoch++;
    _timer?.cancel();
    if (_ready)
      _timer = Timer(
        const Duration(milliseconds: 750),
        () => unawaited(flush()),
      );
  }

  Future<void> flush() async {
    if (_closed || !_ready) return;
    if (_writing) {
      _again = true;
      return;
    }
    _writing = true;
    _writeDone = Completer<void>();
    final epoch = _epoch;
    final identity = _draftIdentity;
    try {
      if (_flushedDraft == identity) return;
      final draft = await model.capturePrivateRecoveryDraft();
      if (_closed || epoch != _epoch) return;
      if (draft == null) {
        await clear();
      } else {
        await _channel.invokeMethod<void>('write', {
          'library': library,
          'json': jsonEncode(draft),
        });
      }
      _flushedDraft = identity;
    } catch (_) {
      // Retain the previous authenticated recovery generation on write failure.
      MobileDiagnostics.record(MobileDiagnostic.draftWriteFailed);
    } finally {
      _writing = false;
      _writeDone?.complete();
      _writeDone = null;
      if (_again && !_closed) {
        _again = false;
        unawaited(flush());
      }
    }
  }

  Future<void> retireResolvedDraft() async {
    if (!_ready) return; // An unresolved recovery copy is not the active draft.
    final ready = _ready;
    _ready = false;
    _timer?.cancel();
    _epoch++;
    try {
      await _writeDone?.future;
      await clear();
    } catch (_) {
      _ready = ready;
      _changed();
      rethrow;
    }
  }

  Future<void> clear() =>
      _channel.invokeMethod<void>('discard', {'library': library});
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      unawaited(flush());
    }
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_changed);
    model.quillController.removeListener(_changed);
    model.htmlController.removeListener(_changed);
    model.titleController.removeListener(_changed);
    model.saveStateNotifier.removeListener(_changed);
  }
}
