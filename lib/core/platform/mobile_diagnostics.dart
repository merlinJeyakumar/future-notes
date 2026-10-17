import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MobileDiagnostic {
  dartStarted('DART_STARTED'),
  startupFailed('DART_STARTUP_FAILED'),
  frameworkError('DART_FRAMEWORK_ERROR'),
  asyncError('DART_ASYNC_ERROR'),
  lifecycle('DART_LIFECYCLE'),
  metrics('DART_METRICS'),
  memoryPressure('DART_MEMORY_PRESSURE'),
  draftReadFailed('DRAFT_READ_FAILED'),
  draftWriteFailed('DRAFT_WRITE_FAILED'),
  draftRecovered('DRAFT_RECOVERED'),
  jobRecordFailed('JOB_RECORD_FAILED'),
  jobChannelFailed('JOB_CHANNEL_FAILED'),
  jobPhase('DART_JOB_PHASE'),
  viewerFailed('VIEWER_FAILED');

  const MobileDiagnostic(this.wireName);
  final String wireName;
}

/// Mobile-only, bounded diagnostic traffic. No content, filenames, note/job IDs,
/// credentials or raw exception strings. Existing error handling still runs.
class MobileDiagnostics {
  static const _channel = MethodChannel('future_notes/diagnostics');
  static bool _installed = false;
  static int _inFlight = 0;

  static void install() {
    if (_installed) return;
    _installed = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record(MobileDiagnostic.frameworkError);
      previousFlutter?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousAsync = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      record(MobileDiagnostic.asyncError);
      return previousAsync?.call(error, stack) ?? false;
    };
    record(MobileDiagnostic.dartStarted);
  }

  static void record(
    MobileDiagnostic event, [
    Map<String, num> metrics = const {},
  ]) {
    if (_inFlight >= 16) return;
    _inFlight++;
    unawaited(_send(event, metrics));
  }

  static Future<void> _send(
    MobileDiagnostic event,
    Map<String, num> metrics,
  ) async {
    try {
      await _channel.invokeMethod<void>('record', {
        'event': event.wireName,
        'metrics': metrics,
      });
    } catch (_) {
      // Diagnostic transport must never affect editing, recovery or jobs.
    } finally {
      _inFlight--;
    }
  }
}
