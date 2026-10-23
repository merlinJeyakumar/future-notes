import 'package:flutter/material.dart';
import '../../../core/theme/app_dialog.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_viewer.dart';

// Weak ownership prevents retained view models; cards and mentions share intents.
final _intents = Expando<Set<String>>('attachment preview intents');

Future<void> openAttachmentPreview(
  BuildContext context,
  ContentViewModel model,
  AttachmentModel attachment, {
  bool system = false,
  FocusNode? restoreFocus,
  AttachmentPlayerFactory? playerFactory,
}) async {
  final owner = model.draftSession.generation;
  final credentials = model.draftSession.credentialGeneration;
  final path = model.currentContentPath;
  final key = '$owner/$credentials/$path/${attachment.id}';
  bool current() =>
      context.mounted &&
      !model.isLocked &&
      owner == model.draftSession.generation &&
      credentials == model.draftSession.credentialGeneration &&
      path == model.currentContentPath &&
      model.attachments.any((a) => a.id == attachment.id);
  if (!current()) return;
  final intents = _intents[model] ??= <String>{};
  if (!intents.add(key)) return;
  // Preview return must not reopen the editor keyboard through focus history.
  restoreFocus?.unfocus();
  try {
    final result = await model.openAttachment(attachment, system: system);
    if (!context.mounted || !current() || !result.isSuccess || system) return;
    await showAppDialog<void>(
      context: context,
      builder: (_) => AttachmentViewer(
        viewModel: model,
        attachment: attachment,
        file: result.value!,
        playerFactory: playerFactory,
      ),
    );
  } finally {
    intents.remove(key);
  }
}
