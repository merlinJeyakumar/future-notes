import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The Mac Find input keeps focus when the platform submits a search.
/// Quill's default input treats submission as Done and unfocuses the field.
class MacosNoteFindDialog extends StatefulWidget {
  const MacosNoteFindDialog({super.key, required this.controller});

  final QuillController controller;

  @override
  State<MacosNoteFindDialog> createState() => _MacosNoteFindDialogState();
}

class _MacosNoteFindDialogState extends State<MacosNoteFindDialog> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Find in note');
  Timer? _searchTimer;
  List<int> _offsets = [];
  int _index = 0;
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _showSettings = false;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _queryChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), _find);
  }

  void _find() {
    _searchTimer?.cancel();
    final previous = _offsets.isEmpty ? 0 : _offsets[_index];
    setState(() {
      _offsets = _text.text.isEmpty
          ? []
          : widget.controller.document.search(
              _text.text,
              caseSensitive: _caseSensitive,
              wholeWord: _wholeWord,
            );
      final next = _offsets.indexWhere((offset) => offset >= previous);
      _index = next < 0 ? 0 : next;
    });
    _selectMatch();
  }

  void _selectMatch() {
    final controller = widget.controller;
    if (_offsets.isEmpty) {
      controller.updateSelection(
        TextSelection.collapsed(offset: controller.selection.baseOffset),
        ChangeSource.local,
      );
      return;
    }
    final offset = _offsets[_index];
    final length = controller.queryNode(offset) is Embed
        ? 1
        : _text.text.length;
    controller.updateSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + length),
      ChangeSource.local,
    );
  }

  void _move(int direction) {
    if (_searchTimer?.isActive ?? false) {
      _find();
      return;
    }
    if (_offsets.isEmpty) return;
    setState(() => _index = (_index + direction) % _offsets.length);
    _selectMatch();
  }

  void _submit(String _) {
    // A composing IME owns its confirmation until the platform commits it.
    if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
      return;
    }
    _move(1);
  }

  @override
  Widget build(BuildContext context) {
    final loc = FlutterQuillLocalizations.of(context)!;
    final match = _text.text.isEmpty
        ? ''
        : _offsets.isEmpty
        ? '0/0'
        : '${_index + 1}/${_offsets.length}';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      alignment: Alignment.bottomCenter,
      insetPadding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showSettings)
            SizedBox(
              height: 45,
              child: Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        loc.caseSensitive,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: _caseSensitive,
                      onChanged: (value) {
                        _caseSensitive = value!;
                        _find();
                      },
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        loc.wholeWord,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: _wholeWord,
                      onChanged: (value) {
                        _wholeWord = value!;
                        _find();
                      },
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 45,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: loc.close,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  isSelected: _caseSensitive || _wholeWord,
                  tooltip: loc.searchSettings,
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      setState(() => _showSettings = !_showSettings),
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: match,
                    ),
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onChanged: _queryChanged,
                    // Override Flutter's default Done -> unfocus behavior.
                    onEditingComplete: () {},
                    onSubmitted: _submit,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: loc.moveToPreviousOccurrence,
                  onPressed: _offsets.isEmpty ? null : () => _move(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: loc.moveToNextOccurrence,
                  onPressed: _offsets.isEmpty ? null : () => _move(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
