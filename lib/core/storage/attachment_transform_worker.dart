import 'dart:async';
import 'dart:isolate';

import '../operations/operation_result.dart';
import 'streaming_file_cipher.dart';

class FileTransformRequest {
  const FileTransformRequest({
    required this.source,
    required this.destination,
    required this.decryptSource,
    required this.encryptDestination,
    this.sourcePassword,
    this.destinationPassword,
  });
  final StreamingFileSource source;
  final String destination;
  final bool decryptSource;
  final bool encryptDestination;
  final String? sourcePassword;
  final String? destinationPassword;
}

/// Own one transform at a time; queued requests contain descriptors, not bytes.
/// Cancel is acknowledged only after the operation's file handles are closed.
class AttachmentTransformWorker {
  Future<void> _tail = Future.value();
  bool _closing = false;
  Future<void> close() async {
    _closing = true;
    await _tail;
  }

  FileTransformJob submit(
    FileTransformRequest request, {
    FileByteProgress? onProgress,
  }) {
    final job = FileTransformJob._();
    if (_closing) {
      job._completed.complete(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Attachment worker is closing.',
        ),
      );
      return job;
    }
    _tail = _tail.then((_) async {
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
      final events = ReceivePort();
      final result = Completer<OperationResult<CipherFileResult>>();
      final ended = Completer<void>();
      final listener = events.listen((message) {
        if (message is SendPort) {
          job._cancelPort = message;
          if (job._cancelled) message.send(true);
        } else if (message is _Progress) {
          try {
            onProgress?.call(message.phase, message.bytes, message.total);
          } catch (_) {
            /* UI callbacks cannot strand worker ownership. */
          }
        } else if (message is OperationResult<CipherFileResult>) {
          if (!result.isCompleted) result.complete(message);
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
          _Start(events.sendPort, request),
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
        job._completed.complete(await result.future);
      } catch (_) {
        job._completed.complete(
          const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Attachment worker could not start.',
          ),
        );
      } finally {
        job._cancelPort = null;
        await listener.cancel();
        events.close();
      }
    });
    return job;
  }

  static void _entry(_Start start) async {
    final cancellation = ReceivePort();
    var cancelled = false;
    cancellation.listen((_) => cancelled = true);
    start.events.send(cancellation.sendPort);
    OperationResult<CipherFileResult> result;
    try {
      final request = start.request;
      result = OperationResult.success(
        await StreamingFileCipher.transform(
          source: request.source,
          destination: request.destination,
          decryptSource: request.decryptSource,
          encryptDestination: request.encryptDestination,
          sourcePassword: request.sourcePassword,
          destinationPassword: request.destinationPassword,
          cancelled: () => cancelled,
          progress: (phase, bytes, total) =>
              start.events.send(_Progress(phase, bytes, total)),
        ),
      );
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
    cancellation.close();
    Isolate.exit(start.events, result);
  }
}

class FileTransformJob {
  FileTransformJob._();
  final _completed = Completer<OperationResult<CipherFileResult>>();
  bool _cancelled = false;
  bool _started = false;
  SendPort? _cancelPort;
  Future<OperationResult<CipherFileResult>> get result => _completed.future;
  Future<OperationResult<CipherFileResult>> cancel() {
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

class _Start {
  const _Start(this.events, this.request);
  final SendPort events;
  final FileTransformRequest request;
}

class _Progress {
  const _Progress(this.phase, this.bytes, this.total);
  final String phase;
  final int bytes;
  final int total;
}
