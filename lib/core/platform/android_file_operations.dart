import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../operations/file_operation_host.dart';
import 'mobile_diagnostics.dart';

/// Holds the application's existing engine through an acknowledged native
/// foreground-service lease. Nested work shares a reference-counted lifetime.
class AndroidFileOperations implements FileOperationHost {
  AndroidFileOperations({
    MethodChannel channel = const MethodChannel('future_notes/jobs'),
    String? operatingSystem,
    this.heartbeatInterval = const Duration(seconds: 20),
  }) : _channel = channel,
       _android = (operatingSystem ?? Platform.operatingSystem) == 'android';

  static final shared = AndroidFileOperations();
  final MethodChannel _channel;
  final bool _android;
  final Duration heartbeatInterval;
  final _zoneKey = Object();

  @override
  Future<T> runFileOperation<T>(
    FileOperationKind kind,
    Future<T> Function() action,
  ) {
    if (!_android) return action();
    final inherited = Zone.current[_zoneKey];
    if (inherited is _Lease && inherited.references > 0) {
      inherited.references++;
      return Future<T>.sync(action).whenComplete(() => _release(inherited));
    }
    return _run(kind, action);
  }

  Future<T> _run<T>(FileOperationKind kind, Future<T> Function() action) async {
    final lease = _Lease(const Uuid().v4());
    // Do not begin file I/O before Android acknowledges the service lifetime.
    await _channel.invokeMethod<void>('beginFileOperation', {
      'id': lease.id,
      'operation': kind.name,
    });
    lease.heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (!lease.sending && lease.references > 0) {
        lease.sending = true;
        unawaited(
          _channel
              .invokeMethod<void>('fileOperationHeartbeat', {'id': lease.id})
              .catchError((Object _) {
                MobileDiagnostics.record(MobileDiagnostic.jobChannelFailed);
              })
              .whenComplete(() => lease.sending = false),
        );
      }
    });
    return runZoned(
      () => Future<T>.sync(action).whenComplete(() => _release(lease)),
      zoneValues: {_zoneKey: lease},
    );
  }

  Future<void> _release(_Lease lease) async {
    if (--lease.references != 0) return;
    lease.heartbeat?.cancel();
    try {
      await _channel.invokeMethod<void>('endFileOperation', {'id': lease.id});
    } catch (_) {
      // Keep the operation's actual storage result; the native lease itself
      // carries no write authorization and cannot replay a mutation.
      MobileDiagnostics.record(MobileDiagnostic.jobChannelFailed);
    }
  }
}

class _Lease {
  _Lease(this.id);
  final String id;
  int references = 1;
  bool sending = false;
  Timer? heartbeat;
}
