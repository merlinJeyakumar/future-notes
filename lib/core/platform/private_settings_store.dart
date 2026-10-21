import 'dart:convert';
import 'package:flutter/services.dart';

abstract interface class PrivateSettingsStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> metadata);
}

/// Bounded, platform-private preference publication, separate from live notes,
/// SAF/bookmarks, encrypted drafts and background job records.
class NativePrivateSettingsStore implements PrivateSettingsStore {
  const NativePrivateSettingsStore({
    MethodChannel channel = const MethodChannel('future_notes/files'),
  }) : _channel = channel;
  final MethodChannel _channel;
  static const maximumBytes = 64 * 1024;

  @override
  Future<Map<String, dynamic>?> read() async {
    final encoded = await _channel.invokeMethod<String>('readSettings');
    if (encoded == null) return null;
    if (utf8.encode(encoded).length > maximumBytes)
      throw const FormatException('Settings exceed their bound.');
    final metadata = jsonDecode(encoded);
    if (metadata is! Map<String, dynamic>)
      throw const FormatException('Invalid private settings.');
    return metadata;
  }

  @override
  Future<void> write(Map<String, dynamic> metadata) async {
    final encoded = jsonEncode(metadata);
    if (utf8.encode(encoded).length > maximumBytes)
      throw const FormatException('Settings exceed their bound.');
    await _channel.invokeMethod<void>('writeSettings', {'json': encoded});
  }
}
