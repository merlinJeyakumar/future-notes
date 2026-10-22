import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'additional_mobile_jobs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../features/dashboard/models/attachment_job.dart';
import '../../features/dashboard/viewmodels/content_viewmodel.dart';
import '../operations/operation_result.dart';
import 'system_capacity.dart';
import 'mobile_diagnostics.dart';
import '../storage/attachment_scheduler.dart';

/// One UI binding to the application-owned native job host. It observes existing
/// jobs and forwards cancellation to their existing coordinator.
class MobileJobBinding {
  MobileJobBinding(
    this.model, {
    this.onNotification,
    this.additional,
    String? operatingSystem,
  }) : _operatingSystem = operatingSystem ?? Platform.operatingSystem {
    _owner = this;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'memoryPressure') {
        if (call.arguments case final Map capacity) {
          SystemCapacityProbe.reportMobile(
            Map<Object?, Object?>.from(capacity),
          );
          AttachmentScheduler.shared.refresh();
        }
        return;
      }
      if (call.method == 'jobNotification') {
        await _takeNotification();
        return;
      }
      if (call.method == 'interruptedJobsChanged') {
        final encoded = call.arguments;
        if (!_closed && encoded is String) {
          retained.value = (jsonDecode(encoded) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _countNotifications();
        }
        return;
      }
      if (call.method == 'cancelJob') {
        final id = (call.arguments as Map?)?['id'];
        if (id is String) {
          for (final state in allJobs.value.toList()) {
            final job = state.progress.value;
            if (job.id == id && job.cancellable) {
              await cancel(id);
              break;
            }
          }
        }
        _refresh(); // Drop an already-settled native notification as well.
        return;
      }
      if (call.method == 'cancelSafeJobs' || call.method == 'timeout') {
        await _cancelSafeJobs();
        if (call.method == 'timeout')
          _report(
            Platform.isAndroid
                ? 'Android ended this background-processing window. Reopen the app to recover or retry unfinished work.'
                : 'The system ended this background-processing window. Reopen the app to recover or retry unfinished work.',
          );
      }
    });
    model.attachmentJobsNotifier.addListener(_refresh);
    additional?.jobs.addListener(_refresh);
    interrupted = _initialize();
  }
  static const _channel = MethodChannel('future_notes/jobs');
  final ContentViewModel model;
  final AdditionalMobileJobs? additional;
  final String _operatingSystem;
  final allJobs = ValueNotifier<List<AttachmentJobState>>([]);
  Future<void> cancel(String id) =>
      additional?.jobs.value.any((j) => j.progress.value.id == id) == true
      ? additional!.cancel(id)
      : model.cancelAttachmentJob(id);
  Map<String, Object?>? recovery(String id) =>
      additional?.recovery(id) ?? model.attachmentJobRecovery(id);
  final ValueChanged<String>? onNotification;
  final notificationCount = ValueNotifier<int>(0);
  final activeCount = ValueNotifier<int>(0);
  final _listeners = <AttachmentJobState, void Function()>{};
  Timer? _timer;
  Timer? _poll;
  static MobileJobBinding? _owner;
  bool _closed = false;
  bool _sending = false;
  bool _again = false;
  bool _ready = false;
  int _jobSequence = 0;
  final retained = ValueNotifier<List<Map<String, dynamic>>>([]);
  late final Future<List<Map<String, dynamic>>> interrupted;
  Future<List<Map<String, dynamic>>> _initialize() async {
    var retained = <Map<String, dynamic>>[];
    try {
      final encoded = await _channel.invokeMethod<String>('interruptedJobs');
      if (encoded != null)
        retained = (jsonDecode(encoded) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    } catch (_) {
      MobileDiagnostics.record(MobileDiagnostic.jobRecordFailed);
      _report(
        'The unfinished-job record could not be read. Recoverable library objects were retained.',
      );
    }
    if (!_closed) this.retained.value = retained;
    _ready = true;
    _refresh();
    unawaited(_takeNotification());
    return retained;
  }

  Future<void> _takeNotification() async {
    if (_closed ||
        !_ready ||
        (_operatingSystem != 'android' && _operatingSystem != 'ios'))
      return;
    try {
      final id = await _channel.invokeMethod<String>('takeNotification');
      if (!_closed && id != null) onNotification?.call(id);
    } on PlatformException {
      // The in-app per-job notifications remain available.
    }
  }

  void _countNotifications() {
    if (_closed) return;
    final activeIds = {
      for (final state in allJobs.value)
        if (state.progress.value.active) state.progress.value.id,
    };
    activeCount.value = activeIds.length;
    final ids = {
      ...activeIds,
      for (final record in retained.value) record['id'],
    };
    notificationCount.value = ids.length;
  }

  void _refresh() {
    if (_closed || !_ready) return;
    final merged = [
      ...model.attachmentJobsNotifier.value,
      ...?additional?.jobs.value,
    ];
    if (!listEquals(merged, allJobs.value))
      allJobs.value = List.unmodifiable(merged);
    _countNotifications();
    final current = allJobs.value.toSet();
    _owner = this;
    if (current.any((job) => job.progress.value.active)) {
      _poll ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_send()),
      );
    } else {
      _poll?.cancel();
      _poll = null;
    }
    for (final entry in _listeners.entries.toList()) {
      if (!current.contains(entry.key)) {
        entry.key.progress.removeListener(entry.value);
        _listeners.remove(entry.key);
      }
    }
    for (final job in current) {
      if (_listeners.containsKey(job)) continue;
      var phase = job.progress.value.phase;
      final sequence = ++_jobSequence;
      final clock = Stopwatch()..start();
      void recordPhase() =>
          MobileDiagnostics.record(MobileDiagnostic.jobPhase, {
            'job': sequence,
            'phase': job.progress.value.phase.index,
            'operation': job.progress.value.operation.index,
            'elapsed_ms': clock.elapsedMilliseconds,
          });
      recordPhase();
      void changed() {
        if (phase != job.progress.value.phase) {
          phase = job.progress.value.phase;
          recordPhase();
          _refresh();
        } else {
          _timer ??= Timer(const Duration(milliseconds: 500), () {
            _timer = null;
            unawaited(_send());
          });
        }
      }

      _listeners[job] = changed;
      job.progress.addListener(changed);
    }
    unawaited(_send());
  }

  Future<void> _send() async {
    if (_closed) return;
    if (_sending) {
      _again = true;
      return;
    }
    _sending = true;
    try {
      final jobs = [
        for (final state in allJobs.value)
          if (state.progress.value.active)
            {
              'id': state.progress.value.id,
              'fileName': state.progress.value.fileName,
              'phase': state.progress.value.phase.name,
              'detail': state.progress.value.detail,
              'operation': state.progress.value.operation.name,
              'cancellable': state.progress.value.cancellable,
              'bytes': state.progress.value.bytes,
              'total': state.progress.value.total,
              if (state.progress.value.fileProgress case final file?) ...{
                'currentBytes': file.bytes,
                'currentTotal': file.total,
              },
              if (recovery(state.progress.value.id) case final recovery?)
                'recovery': recovery,
            },
      ];
      final capacity = await _channel.invokeMethod<Map<Object?, Object?>>(
        'update',
        {'jobs': jobs},
      );
      if (capacity != null) SystemCapacityProbe.reportMobile(capacity);
    } on PlatformException catch (error) {
      MobileDiagnostics.record(MobileDiagnostic.jobChannelFailed);
      await _cancelSafeJobs();
      _report(
        error.message ??
            'Background processing is unavailable. Keep the app open and retry.',
      );
    } finally {
      _sending = false;
      if (_again && !_closed) {
        _again = false;
        unawaited(_send());
      }
    }
  }

  Future<void> _cancelSafeJobs() async {
    for (final state in allJobs.value.toList()) {
      final job = state.progress.value;
      if (job.cancellable) await cancel(job.id);
    }
  }

  Future<void> dismissInterruptedNotification(String id) async {
    if (!retained.value.any((record) => record['id'] == id)) return;
    await _channel.invokeMethod<void>('dismissInterruptedNotification', {
      'ids': [id],
    });
    if (!_closed)
      retained.value = [
        for (final record in retained.value)
          if (record['id'] == id)
            {...record, 'notificationDismissed': true}
          else
            record,
      ];
  }

  Future<void> acknowledgeInterrupted(String id) async {
    if (retained.value.any((record) => record['id'] == id)) {
      await _channel.invokeMethod<void>('acknowledgeInterrupted', {
        'ids': [id],
      });
      if (!_closed)
        retained.value = retained.value.where((e) => e['id'] != id).toList();
      _countNotifications();
    }
  }

  void _report(String message) {
    if (!_closed)
      model.operationResultNotifier.value = OperationResult.failure(
        OperationOutcome.ioFailure,
        message,
      );
  }

  void dispose() {
    _closed = true;
    retained.dispose();
    notificationCount.dispose();
    activeCount.dispose();
    _timer?.cancel();
    _poll?.cancel();
    model.attachmentJobsNotifier.removeListener(_refresh);
    additional?.jobs.removeListener(_refresh);
    allJobs.dispose();
    for (final entry in _listeners.entries) {
      entry.key.progress.removeListener(entry.value);
    }
    _listeners.clear();
    if (identical(_owner, this)) {
      _owner = null;
      _channel.setMethodCallHandler(null);
    }
  }
}
