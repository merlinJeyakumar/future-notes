import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Multiplexed by opaque tree identity so an old dashboard cannot unregister a
/// newly selected library. Notifications are hints; revision checks own writes.
class MobileLibraryEvents {
  static const _channel = MethodChannel('future_notes/library_events');
  static final _listeners = <String, Set<void Function()>>{};
  static Future<void> Function() listen(
    String library,
    void Function() changed,
  ) {
    if (!Platform.isAndroid) return () async {};
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') {
        final token = call.arguments as String?;
        for (final callback in [...?_listeners[token]]) {
          callback();
        }
      }
    });
    final listeners = _listeners.putIfAbsent(library, () => {});
    listeners.add(changed);
    unawaited(
      _channel.invokeMethod<void>('watch', {'library': library}).catchError((
        Object _,
      ) {
        /* Resume/Refresh still recheck the granted tree. */
      }),
    );
    return () async {
      listeners.remove(changed);
      if (listeners.isEmpty) {
        _listeners.remove(library);
        await _channel.invokeMethod<void>('unwatch', {'library': library});
      }
    };
  }
}
