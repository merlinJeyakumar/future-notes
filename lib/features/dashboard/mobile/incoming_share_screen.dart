import 'package:flutter/material.dart';
import '../../../core/platform/incoming_share_inbox.dart';
import '../../../core/theme/app_dialog.dart';
import '../models/note_model.dart';
import '../models/note_list_ui_state.dart';
import '../models/shared_attachment_target.dart';
import '../viewmodels/content_viewmodel.dart';
import '../widgets/password_dialog.dart';
import '../widgets/attachment_presentation.dart' show formatAttachmentBytes;
import 'shared_attachment_jobs.dart';

class IncomingShareResult {
  const IncomingShareResult(this.target, this.openEditor) : importSource = null;
  const IncomingShareResult.importPackage(this.importSource)
    : target = null,
      openEditor = false;
  final SharedAttachmentTarget? target;
  final bool openEditor;
  final Map<Object?, Object?>? importSource;
}

class IncomingShareScreen extends StatefulWidget {
  const IncomingShareScreen({
    super.key,
    required this.batch,
    required this.jobs,
    required this.model,
  });
  final IncomingSharedBatch batch;
  final SharedAttachmentJobs jobs;
  final ContentViewModel model;
  @override
  State<IncomingShareScreen> createState() => _IncomingShareScreenState();
}

class _IncomingShareScreenState extends State<IncomingShareScreen> {
  final _search = TextEditingController();
  final _title = TextEditingController(text: 'New Note');
  final _password = TextEditingController();
  bool _new = false, _busy = false, _expanded = false;
  bool _openAfter = true;
  SharedAttachmentTarget? _target;
  String? _error;
  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _select(RecentFile note) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      SharedAttachmentTarget? target;
      try {
        target = await widget.model.prepareSharedTarget(note.path);
      } on SharedAttachmentPasswordRequired {
        if (!mounted) return;
        final confirmed = await showAppDialog<String>(
          context: context,
          builder: (_) => PasswordDialog(
            title: 'Unlock note',
            description: note.title,
            onConfirm: (_) {},
            onVerifyCurrent: (password) async {
              try {
                target = await widget.model.prepareSharedTarget(
                  note.path,
                  password: password,
                  rememberPassword: false,
                );
                return true;
              } catch (_) {
                return false;
              }
            },
          ),
        );
        target = confirmed == null
            ? null
            : await widget.model.prepareSharedTarget(
                note.path,
                password: confirmed,
              );
      }
      if (mounted && target != null)
        setState(() {
          _target = target;
          _new = false;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'This note is unavailable. Refresh the library and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(bool editor) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = _new
          ? await widget.model.createSharedNote(
              _title.text,
              _password.text.isEmpty ? null : _password.text,
            )
          : _target!;
      await widget.jobs.start(widget.batch, target);
      if (mounted) Navigator.pop(context, IncomingShareResult(target, editor));
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Files could not be submitted. Existing notes were retained. Share the files again to retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPackage() async {
    final packages = widget.batch.notePackages;
    if (_busy || packages.isEmpty) return;
    final selected = packages.length == 1
        ? packages.single
        : await showAppDialog<Map<Object?, Object?>>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const Text('Choose note package'),
              children: [
                for (final source in packages)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, source),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(
                        source['name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        formatAttachmentBytes(source['length'] as int),
                      ),
                    ),
                  ),
              ],
            ),
          );
    if (mounted && selected != null)
      Navigator.pop(context, IncomingShareResult.importPackage(selected));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<NoteListUiState>(
    valueListenable: widget.model.noteListStateNotifier,
    builder: (context, list, _) => _buildContent(context, list),
  );

  Widget _buildContent(BuildContext context, NoteListUiState list) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = _search.text.toLowerCase();
    final notes = widget.model.shareDestinationNotes
        .where((n) => n.title.toLowerCase().contains(query))
        .toList();
    final sources = widget.batch.sources;
    final total = sources.fold<int>(0, (sum, s) => sum + (s['length'] as int));
    final canAttach =
        !_busy &&
        sources.isNotEmpty &&
        (_new || _target != null) &&
        widget.batch.error == null;
    final content = <Widget>[
      Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                sources.length == 1
                    ? Icons.insert_drive_file_outlined
                    : Icons.file_copy_outlined,
                color: colors.primary,
              ),
              title: Text(
                sources.isEmpty
                    ? 'No files available'
                    : sources.length == 1
                    ? sources.first['name'] as String
                    : '${sources.first['name']} +${sources.length - 1}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${widget.batch.label} · ${formatAttachmentBytes(total)}',
              ),
              trailing: sources.length > 1
                  ? Icon(_expanded ? Icons.expand_less : Icons.expand_more)
                  : null,
              onTap: sources.length > 1
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
            ),
            if (_expanded && sources.length > 1)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final source in sources)
                      ListTile(
                        dense: true,
                        title: Text(
                          source['name'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          formatAttachmentBytes(source['length'] as int),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (widget.batch.notePackages.isNotEmpty) ...[
        const SizedBox(height: 12),
        Material(
          color: colors.primaryContainer.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import a note package',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Restore a shared .fnote package as a note, or attach it as a file below.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: !_busy && widget.batch.error == null
                      ? _importPackage
                      : null,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Validate and Import'),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Text('Attach to a note', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Search notes',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 8),
      _destination(
        icon: Icons.note_add_outlined,
        title: 'New note',
        subtitle: 'Create a note for these files',
        selected: _new,
        onTap: () => setState(() {
          _new = true;
          _target = null;
        }),
      ),
      if (_new)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            children: [
              TextField(
                controller: _title,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                ),
              ),
            ],
          ),
        ),
      for (final note in notes)
        _destination(
          icon: note.isLocked ? Icons.lock_outline : Icons.description_outlined,
          title: note.title,
          subtitle: [
            if (note.isLocked) 'Protected',
            if (note.noteId case final id?)
              'ID ${id.substring(0, id.length < 5 ? id.length : 5)}',
          ].join(' · '),
          selected: !_new && _target?.reference.fileName == note.path,
          onTap: () => _select(note),
        ),
      if (notes.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: list.isScanning
              ? Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Loading notes…',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                )
              : list.error != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes are unavailable.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () => widget.model.loadRecentFiles(),
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Text(
                  query.isEmpty ? 'No notes yet' : 'No matching notes',
                  style: theme.textTheme.bodyMedium,
                ),
        ),
      if (widget.batch.error ?? _error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(error, style: TextStyle(color: colors.error)),
        ),
    ];
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _openAfter,
            onChanged: _busy
                ? null
                : (value) => setState(() => _openAfter = value!),
            title: const Text('Open note after attaching'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: canAttach ? () => _start(_openAfter) : null,
            icon: const Icon(Icons.attach_file),
            label: const Text('Attach files'),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shared files'),
          leading: IconButton(
            tooltip: 'Cancel sharing',
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keep every control reachable when the keyboard or accessibility
              // text leaves too little room for a fixed footer.
              final compact =
                  constraints.maxHeight < 400 ||
                  MediaQuery.textScalerOf(context).scale(16) > 24;
              if (compact) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: content,
                        ),
                      ),
                      if (_busy) const LinearProgressIndicator(),
                      footer,
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: content,
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  footer,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _destination({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: colors.primaryContainer.withValues(alpha: .35),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(icon),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        selected: selected,
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 22,
        ),
        onTap: _busy ? null : onTap,
      ),
    );
  }
}
