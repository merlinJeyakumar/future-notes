import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../platform/android_native_cipher.dart';

import '../operations/operation_result.dart';
import 'streaming_file_cipher.dart';
import 'attachment_scheduler.dart';
import 'native_storage_primitives.dart';
import 'storage_environment.dart';
import '../platform/worker_compute_clock.dart';
import 'preparation_pacer.dart';

class FileTransformRequest {
  const FileTransformRequest({
    required this.source,
    required this.destination,
    required this.decryptSource,
    required this.encryptDestination,
    this.sourcePassword,
    this.destinationPassword,
    this.verifyOutput = true,
    this.expectedPlaintextBytes,
    this.requireWholeSource = false,
  });
  final StreamingFileSource source;
  final String destination;
  final bool decryptSource;
  final bool encryptDestination;
  final String? sourcePassword;
  final String? destinationPassword;
  final bool verifyOutput;
  final int? expectedPlaintextBytes;
  final bool requireWholeSource;
}

class FileRevisionRequest {
  const FileRevisionRequest(this.environment, this.path);
  final StorageEnvironment environment;
  final String path;
}

class FileReadCancellation {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  final _listeners = <void Function()>{};
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}

/// Owned transforms share a process-wide adaptive preparation budget.
/// Cancel is acknowledged only after the operation's file handles are closed.
class AttachmentTransformWorker {
  AttachmentTransformWorker({AttachmentScheduler? scheduler})
    : _scheduler = scheduler ?? AttachmentScheduler.shared;
  final AttachmentScheduler _scheduler;
  final _jobs = <Future<void>>{};
  bool _closing = false;
  Future<void> close() async {
    _closing = true;
    await Future.wait(_jobs.toList());
  }

  FileTransformJob submit(
    FileTransformRequest request, {
    FileByteProgress? onProgress,
    void Function()? onStarted,
  }) {
    final job = FileTransformJob._();
    _enqueue(request, job, onProgress, onStarted);
    return job;
  }

  FileWorkerJob<StorageRevision> inspect(
    FileRevisionRequest request, {
    FileByteProgress? onProgress,
    FileReadCancellation? cancellation,
  }) {
    final job = FileWorkerJob<StorageRevision>._();
    try {
      onProgress?.call('Queued', 0, 0);
    } catch (_) {
      /* Observer only. */
    }
    final detach = cancellation?.listen(() {
      unawaited(job.cancel());
    });
    unawaited(job.result.then((_) => detach?.call()));
    return _enqueue(request, job, onProgress, null);
  }

  FileWorkerJob<T> _enqueue<T>(
    Object request,
    FileWorkerJob<T> job,
    FileByteProgress? onProgress,
    void Function()? onStarted,
  ) {
    if (job._completed.isCompleted) return job;
    if (_closing) {
      job._completed.complete(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Attachment worker is closing.',
        ),
      );
      return job;
    }
    Future<void> task;
    try {
      task = _scheduler.schedule(
        () async {
          if (job._cancelled) {
            if (!job._completed.isCompleted) {
              job._completed.complete(
                const OperationResult.failure(
                  OperationOutcome.cancelled,
                  'Attachment preparation cancelled.',
                ),
              );
            }
            return;
          }
          // No await before marking ownership: cancellation can settle immediately
          // only while no isolate or file handle has been acquired.
          job._started = true;
          try {
            onStarted?.call();
          } catch (_) {
            /* Observer cannot strand ownership. */
          }
          final events = ReceivePort();
          final result = Completer<OperationResult<T>>();
          final ended = Completer<void>();
          final nativeOwner = AndroidNativeCipher.ready
              ? const Uuid().v4()
              : null;
          OperationResult<T>? resolved;
          final listener = events.listen((message) {
            if (message is SendPort) {
              job._cancelPort = message;
              message.send(_WorkerBudget(job._duty));
              if (job._cancelled) message.send(true);
            } else if (message is _Progress) {
              try {
                onProgress?.call(message.phase, message.bytes, message.total);
              } catch (_) {
                /* UI callbacks cannot strand worker ownership. */
              }
            } else if (message is OperationResult) {
              if (!result.isCompleted) {
                result.complete(
                  !message.isSuccess
                      ? OperationResult<T>.failure(
                          message.outcome,
                          message.message,
                        )
                      : message.value is T
                      ? OperationResult<T>.success(message.value as T)
                      : OperationResult<T>.failure(
                          OperationOutcome.ioFailure,
                          'Invalid worker response.',
                        ),
                );
              }
            } else if (message == null) {
              if (!ended.isCompleted) ended.complete();
            } else if (message is List) {
              if (!result.isCompleted) {
                result.complete(
                  const OperationResult.failure(
                    OperationOutcome.ioFailure,
                    'Attachment worker failed.',
                  ),
                );
              }
            }
          });
          try {
            await Isolate.spawn(
              _entry,
              _Start(
                events.sendPort,
                request,
                job._duty,
                AndroidNativeCipher.ready
                    ? ServicesBinding.rootIsolateToken
                    : null,
                nativeOwner,
              ),
              onError: events.sendPort,
              onExit: events.sendPort,
              errorsAreFatal: true,
            );
            await ended.future;
            // Terminal result and exit share one port, so ordering does not rely on
            // a timer or inter-port delivery timing. The worker's files are closed.
            if (!result.isCompleted) {
              result.complete(
                const OperationResult.failure(
                  OperationOutcome.ioFailure,
                  'Attachment worker exited unexpectedly.',
                ),
              );
            }
            resolved = await result.future;
          } catch (_) {
            resolved = const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Attachment worker could not start.',
            );
          } finally {
            await AndroidNativeCipher.releaseOwner(nativeOwner);
            job._cancelPort = null;
            await listener.cancel();
            events.close();
          }
          job._completed.complete(resolved);
        },
        cancelled: () => job._cancelled,
        quota: (duty) {
          job._duty = duty;
          job._cancelPort?.send(_WorkerBudget(duty));
        },
      );
    } catch (_) {
      job._completed.complete(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Attachment queue is full. Wait for a file to finish and retry.',
        ),
      );
      return job;
    }
    _jobs.add(task);
    task.then<void>(
      (_) {
        _jobs.remove(task);
      },
      onError: (Object error, StackTrace stack) {
        _jobs.remove(task);
        if (!job._completed.isCompleted) {
          job._completed.complete(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Attachment scheduling failed.',
            ),
          );
        }
      },
    );
    return job;
  }

  static void _entry(_Start start) async {
    AndroidNativeCipher.initialize(start.nativeToken, owner: start.nativeOwner);
    final cancellation = ReceivePort();
    var cancelled = false;
    var duty = start.duty;
    cancellation.listen((message) {
      if (message is _WorkerBudget) {
        duty = message.duty;
      } else {
        cancelled = true;
      }
    });
    final compute = WorkerComputeClock();
    final pacer = PreparationPacer(
      workedMicros: compute.take,
      duty: () => duty,
      cancelled: () => cancelled,
    );

    start.events.send(cancellation.sendPort);
    OperationResult<Object?> result;
    try {
      final request = start.request;
      if (request is FileRevisionRequest) {
        await request.environment.verifyLocation(request.path);
        var total = 0;
        final progressClock = Stopwatch()..start();
        var reported = -100;
        final revision = await NativeStoragePrimitives(request.environment)
            .captureRevision(
              request.path,
              onStart: (length) {
                if (length > StreamingFileCipher.maxAttachmentBytes + 32) {
                  throw const FormatException('Attachment exceeds limit.');
                }
                total = length;
                start.events.send(_Progress('Checking attachment', 0, total));
              },
              onChunk: (bytes) async {
                await pacer.cooperate();
                if (cancelled) throw const FileJobCancelled();
                if (bytes == total ||
                    progressClock.elapsedMilliseconds - reported >= 100) {
                  reported = progressClock.elapsedMilliseconds;
                  start.events.send(
                    _Progress('Checking attachment', bytes, total),
                  );
                }
              },
              beginCompute: compute.begin,
              endCompute: compute.end,
            );
        if (cancelled) throw const FileJobCancelled();
        result = OperationResult<StorageRevision>.success(revision);
      } else if (request is FileTransformRequest) {
        result = OperationResult.success(
          await StreamingFileCipher.transform(
            source: request.source,
            destination: request.destination,
            decryptSource: request.decryptSource,
            encryptDestination: request.encryptDestination,
            sourcePassword: request.sourcePassword,
            destinationPassword: request.destinationPassword,
            verifyOutput: request.verifyOutput,
            expectedPlaintextBytes: request.expectedPlaintextBytes,
            requireWholeSource: request.requireWholeSource,
            duty: () => duty,
            cancelled: () => cancelled,
            cooperate: pacer.cooperate,
            beginCompute: compute.begin,
            endCompute: compute.end,
            progress: (phase, bytes, total) =>
                start.events.send(_Progress(phase, bytes, total)),
          ),
        );
      } else {
        throw const FormatException('Unknown worker request.');
      }
    } on FileJobCancelled {
      result = const OperationResult.failure(
        OperationOutcome.cancelled,
        'Attachment preparation cancelled.',
      );
    } on FormatException {
      result = const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Attachment source or ciphertext is invalid.',
      );
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Attachment preparation failed; the original was retained.',
      );
    }
    compute.close();
    cancellation.close();
    Isolate.exit(start.events, result);
  }
}

class FileTransformJob extends FileWorkerJob<CipherFileResult> {
  FileTransformJob._() : super._();
}

class FileWorkerJob<T> {
  FileWorkerJob._();
  final _completed = Completer<OperationResult<T>>();
  bool _cancelled = false;
  bool _started = false;
  SendPort? _cancelPort;
  double _duty = 1;
  Future<OperationResult<T>> get result => _completed.future;
  Future<OperationResult<T>> cancel() {
    _cancelled = true;
    if (!_started && !_completed.isCompleted) {
      _completed.complete(
        const OperationResult.failure(
          OperationOutcome.cancelled,
          'Attachment preparation cancelled.',
        ),
      );
    }
    _cancelPort?.send(true);
    return result;
  }
}

class _WorkerBudget {
  const _WorkerBudget(this.duty);
  final double duty;
}

class _Start {
  const _Start(
    this.events,
    this.request,
    this.duty,
    this.nativeToken,
    this.nativeOwner,
  );
  final SendPort events;
  final Object request;
  final double duty;
  final RootIsolateToken? nativeToken;
  final String? nativeOwner;
}

class _Progress {
  const _Progress(this.phase, this.bytes, this.total);
  final String phase;
  final int bytes;
  final int total;
}
