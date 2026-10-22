import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/library_watch.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';

void main() {
  late _Surface surface;
  late NativeLibraryWatch watch;
  late StreamSubscription<void> subscription;
  var changes = 0;
  final failures = <Object>[];
  setUp(() async {
    surface = _Surface();
    changes = 0;
    failures.clear();
    watch = await NativeLibraryWatch.open(
      StorageBinding(surface.root, 7),
      verify: (_) async {},
      watch: surface.open,
      exists: (path) async => surface.present.contains(path),
    );
    subscription = watch.changes.listen(
      (_) => changes++,
      onError: failures.add,
    );
    await _drain();
    changes = 0;
  });
  tearDown(() async {
    await subscription.cancel();
    await watch.close();
    for (final controller in surface.controllers) {
      await controller.close();
    }
  });

  test('existing root uses recursive events and a shallow parent sentinel', () {
    expect(surface.opens.map((entry) => entry.$2), [false, true]);
    expect(surface.opens.first.$1, p.dirname(surface.root));
    expect(watch.binding.generation, 7);
  });
  test(
    'nested content events refresh while recovery and sibling events do not',
    () async {
      surface.emit(
        surface.root,
        FileSystemModifyEvent(
          p.join(surface.root, 'note_a', 'attachments', 'a.med'),
          false,
          false,
        ),
      );
      surface.emit(
        surface.root,
        FileSystemModifyEvent(
          p.join(surface.root, '.future-notes-recovery', 'receipt'),
          false,
          false,
        ),
      );
      surface.emit(
        p.dirname(surface.root),
        FileSystemModifyEvent(
          p.join(p.dirname(surface.root), 'sibling.enc'),
          false,
          false,
        ),
      );
      await _drain();
      expect(changes, 1);
    },
  );
  test('root recreation reattaches the recursive watch', () async {
    final before = surface.opens.length;
    surface.present.remove(surface.root);
    surface.emit(
      p.dirname(surface.root),
      FileSystemDeleteEvent(surface.root, true),
    );
    await _drain();
    surface.present.add(surface.root);
    surface.emit(
      p.dirname(surface.root),
      FileSystemCreateEvent(surface.root, true),
    );
    await _drain();
    expect(surface.opens.length, greaterThan(before));
    changes = 0;
    surface.emit(
      surface.root,
      FileSystemCreateEvent(p.join(surface.root, 'new.enc'), false),
    );
    await _drain();
    expect(changes, 1);
  });
  test(
    'moving another object into the root refreshes its destination',
    () async {
      surface.emit(
        surface.root,
        FileSystemMoveEvent(
          p.join(p.dirname(surface.root), 'outside.enc'),
          false,
          p.join(surface.root, 'import.enc'),
        ),
      );
      await _drain();
      expect(changes, 1);
    },
  );
  test(
    'native failures expose sanitized state without stopping cleanup',
    () async {
      surface.controllers.last.addError(StateError('synthetic-private-path'));
      await _drain();
      expect(watch.failed, isTrue);
      expect(
        failures.single.toString(),
        isNot(contains('synthetic-private-path')),
      );
    },
  );
  test(
    'closed ownership rejects late events and closes subscriptions once',
    () async {
      await watch.close();
      surface.emit(
        surface.root,
        FileSystemCreateEvent(p.join(surface.root, 'late.enc'), false),
      );
      await _drain();
      expect(changes, 0);
      expect(
        surface.controllers.every((controller) => !controller.hasListener),
        isTrue,
      );
      await watch.close();
    },
  );
  test(
    'a missing root follows creation of each intermediate ancestor',
    () async {
      await watch.close();
      await subscription.cancel();
      surface.present.remove(surface.root);
      surface.present.remove(p.dirname(surface.root));
      watch = await NativeLibraryWatch.open(
        StorageBinding(surface.root, 8),
        verify: (_) async {},
        watch: surface.open,
        exists: (path) async => surface.present.contains(path),
      );
      subscription = watch.changes.listen(
        (_) => changes++,
        onError: failures.add,
      );
      expect(surface.opens.last.$1, p.dirname(p.dirname(surface.root)));
      surface.present.add(p.dirname(surface.root));
      surface.emit(
        p.dirname(p.dirname(surface.root)),
        FileSystemCreateEvent(p.dirname(surface.root), true),
      );
      await _drain();
      expect(surface.opens.last.$1, p.dirname(surface.root));
      surface.present.add(surface.root);
      surface.emit(
        p.dirname(surface.root),
        FileSystemCreateEvent(surface.root, true),
      );
      await _drain();
      expect(surface.opens.last, (surface.root, true));
    },
  );
  test('preparation failure cancels a partially opened sentinel', () async {
    final partial = _Surface();
    await expectLater(
      NativeLibraryWatch.open(
        StorageBinding(partial.root, 1),
        verify: (_) async {},
        exists: (path) async => partial.present.contains(path),
        watch: (path, recursive) {
          if (recursive) throw StateError('synthetic-open-failure');
          return partial.open(path, recursive);
        },
      ),
      throwsStateError,
    );
    expect(
      partial.controllers.every((controller) => !controller.hasListener),
      isTrue,
    );
    for (final controller in partial.controllers) {
      await controller.close();
    }
  });

  test('a scoped folder watch never requests access to its parent', () async {
    final scoped = _Surface();
    final opened = await NativeLibraryWatch.open(
      StorageBinding(scoped.root, 9),
      verify: (_) async {},
      watchAncestors: false,
      exists: (path) async {
        expect(path, scoped.root);
        return scoped.present.contains(path);
      },
      watch: scoped.open,
    );
    expect(scoped.opens, [(scoped.root, true)]);
    final errors = <Object>[];
    final listener = opened.changes.listen((_) {}, onError: errors.add);
    scoped.present.remove(scoped.root);
    scoped.emit(scoped.root, FileSystemDeleteEvent(scoped.root, true));
    await _drain();
    expect(opened.failed, isTrue);
    expect(errors, hasLength(1));
    await listener.cancel();
    await opened.close();
    for (final controller in scoped.controllers) {
      await controller.close();
    }
  });
}

Future<void> _drain() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Surface {
  final root = p.join(
    Directory.systemTemp.path,
    'synthetic-watch-parent',
    'library',
  );
  late final present = {root, p.dirname(root), p.dirname(p.dirname(root))};
  final opens = <(String, bool)>[];
  final controllers = <StreamController<FileSystemEvent>>[];
  Stream<FileSystemEvent> open(String path, bool recursive) {
    opens.add((path, recursive));
    final controller = StreamController<FileSystemEvent>.broadcast();
    controllers.add(controller);
    return controller.stream;
  }

  void emit(String path, FileSystemEvent event) {
    for (var i = opens.length - 1; i >= 0; i--) {
      if (opens[i].$1 == path && controllers[i].hasListener) {
        controllers[i].add(event);
        return;
      }
    }
  }
}
