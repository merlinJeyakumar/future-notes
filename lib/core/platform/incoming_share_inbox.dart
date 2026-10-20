import 'package:flutter/services.dart';

class IncomingSharedBatch {
  IncomingSharedBatch(this.id, this.sources, this.error);
  final String id;
  final List<Map<Object?, Object?>> sources;
  final String? error;
  List<Map<Object?, Object?>> get notePackages => sources
      .where(
        (source) =>
            (source['name'] as String? ?? '').toLowerCase().endsWith('.fnote'),
      )
      .toList(growable: false);
  String get label =>
      '${sources.length} shared ${sources.length == 1 ? 'file' : 'files'}';
  factory IncomingSharedBatch.fromMap(Map value) =>
      IncomingSharedBatch(value['id'] as String, [
        for (final source in value['sources'] as List)
          Map<Object?, Object?>.from(source as Map),
      ], value['error'] as String?);
}

class IncomingShareInbox {
  IncomingShareInbox({
    this.channel = const MethodChannel('future_notes/incoming_shares'),
  });
  final MethodChannel channel;
  void listen(void Function() changed) =>
      channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') changed();
      });
  Future<List<IncomingSharedBatch>> pending() async => [
    for (final value
        in await channel.invokeListMethod<Object?>('pending') ?? [])
      IncomingSharedBatch.fromMap(value as Map),
  ];
  Future<void> acknowledge(String id) =>
      channel.invokeMethod('acknowledge', {'id': id});
  Future<Map<Object?, Object?>> claim(String id, String lease) async {
    final source = await channel.invokeMapMethod<Object?, Object?>('claim', {
      'id': id,
      'lease': lease,
    });
    if (source == null)
      throw StateError('This shared file is no longer available.');
    return source;
  }

  Future<void> discard(String id) =>
      channel.invokeMethod('discard', {'id': id});
  void dispose() => channel.setMethodCallHandler(null);
}
