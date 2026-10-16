import 'dart:async';
import 'package:flutter/material.dart';

/// Blocks conflicting pointer actions immediately without dimming the canvas.
/// Fast reads leave no visual flash; slower reads get an overlay progress line.
class NoteOpeningOverlay extends StatefulWidget {
  const NoteOpeningOverlay({super.key});

  @override
  State<NoteOpeningOverlay> createState() => _NoteOpeningOverlayState();
}

class _NoteOpeningOverlayState extends State<NoteOpeningOverlay> {
  late final Timer _delay;
  bool _showProgress = false;

  @override
  void initState() {
    super.initState();
    _delay = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showProgress = true);
    });
  }

  @override
  void dispose() {
    _delay.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: Semantics(
      label: 'Opening note',
      liveRegion: true,
      child: AbsorbPointer(
        child: SizedBox.expand(
          child: Align(
            alignment: Alignment.topCenter,
            child: _showProgress
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}
