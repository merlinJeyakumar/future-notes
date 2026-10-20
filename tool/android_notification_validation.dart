// Explicit synthetic device probe. Never imported by the normal application.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/jobs');
  final cancelled = <String>{};
  final report = <String, Object?>{};
  var tick = 0;
  Future<void> send() => channel.invokeMethod<void>('update', {
    'jobs': [
      for (var index = 0; index < 3; index++)
        if (!cancelled.contains('fn-notification-probe-$index'))
          {
            'id': 'fn-notification-probe-$index',
            'phase': 'encrypting',
            'operation': 'add',
            'fileName': 'Synthetic job ${index + 1}',
            'detail': 'Encrypting',
            'cancellable': true,
            'bytes': (tick + 1) * 1048576,
            'total': 500 * 1048576,
          },
    ],
  });
  channel.setMethodCallHandler((call) async {
    if (call.method == 'cancelJob') {
      final id = (call.arguments as Map)['id'] as String;
      if (id.startsWith('fn-notification-probe-')) {
        cancelled.add(id);
        await send();
        print('FN_NOTIFICATION_CANCEL ${cancelled.length}');
      }
    }
  });
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Synthetic notification validation')),
      ),
    ),
  );
  try {
    await channel.invokeMethod<String>('interruptedJobs');
    print('FN_NOTIFICATION_RUNNING');
    for (tick = 0; tick < 500; tick++) {
      await send();
      if (tick == 100) {
        print('FN_NOTIFICATION_QUIET');
        await Future<void>.delayed(const Duration(seconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    report['cancelDelivered'] = cancelled.length == 1;
    report['ticks'] = 500;
    report['syntheticJobs'] = 3;
    report['passed'] = cancelled.length == 1;
  } catch (_) {
    report['passed'] = false;
  } finally {
    await channel.invokeMethod<Object?>('update', {'jobs': <Object>[]});
    print('FN_NOTIFICATION_PROBE ${jsonEncode(report)}');
  }
}
