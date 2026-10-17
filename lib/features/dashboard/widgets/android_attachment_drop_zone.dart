import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../viewmodels/content_viewmodel.dart';

class AndroidAttachmentDropZone extends StatefulWidget {
  const AndroidAttachmentDropZone({
    super.key,
    required this.model,
    required this.child,
  });
  final ContentViewModel model;
  final Widget child;
  @override
  State<AndroidAttachmentDropZone> createState() =>
      _AndroidAttachmentDropZoneState();
}

class _AndroidAttachmentDropZoneState extends State<AndroidAttachmentDropZone> {
  static const _channel = MethodChannel('future_notes/drop');
  static _AndroidAttachmentDropZoneState? _owner;
  bool _hover = false;
  String? _target;
  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    _owner = this;
    widget.model.addListener(_sync);
    _channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'hover') {
        setState(
          () => _hover =
              call.arguments == true &&
              (ModalRoute.of(context)?.isCurrent ?? true),
        );
      } else if (call.method == 'files') {
        final data = Map<Object?, Object?>.from(call.arguments as Map);
        final sources = (data['sources'] as List)
            .map((e) => Map<Object?, Object?>.from(e as Map))
            .toList();
        final target = data['target'] as String;
        // Always adopt/close native leases, including stale drops and modal UI.
        final result = await widget.model.attachNativeDroppedSources(
          sources,
          (ModalRoute.of(context)?.isCurrent ?? true) ? target : 'dismissed',
        );
        if (!result.isSuccess)
          widget.model.operationResultNotifier.value = result;
      } else if (call.method == 'error') {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(call.arguments as String)));
      }
    });
    _sync();
  }

  void _sync() {
    final target = widget.model.mobileDropTarget;
    if (_target == target) return;
    _target = target;
    unawaited(_channel.invokeMethod<void>('target', {'token': target}));
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      widget.model.removeListener(_sync);
      if (identical(_owner, this)) {
        _owner = null;
        _channel.setMethodCallHandler(null);
        unawaited(_channel.invokeMethod<void>('target', {'token': null}));
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_hover)
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .12),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Drop files to attach to this note',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
