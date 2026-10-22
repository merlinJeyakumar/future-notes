import 'dart:io';

import 'package:path/path.dart' as p;

/// Canonicalize the trusted OS temp root before creating children. macOS can
/// return /var aliases; storage tests must exercise real ownership rather than
/// fail their deliberate no-symlink guards before reaching the behavior.
Future<Directory> createValidationRun([
  String prefix = 'future-notes-validation-',
]) async {
  if (!prefix.startsWith('future-notes-validation-') ||
      prefix.contains('/') ||
      prefix.contains('\\')) {
    throw ArgumentError('A disposable validation prefix is required.');
  }
  final root = Directory(await Directory.systemTemp.resolveSymbolicLinks());
  return root.createTemp(prefix);
}

Directory createValidationRunSync([
  String prefix = 'future-notes-validation-',
]) {
  if (!prefix.startsWith('future-notes-validation-') ||
      prefix.contains('/') ||
      prefix.contains('\\')) {
    throw ArgumentError('A disposable validation prefix is required.');
  }
  final root = Directory(Directory.systemTemp.resolveSymbolicLinksSync());
  return root.createTempSync(prefix);
}

/// Deletes only an operation-owned disposable run under the resolved temp root.
/// Validate the resolved absolute target before any recursive Windows deletion.
Future<void> deleteValidationRun(Directory run) async {
  if (!await run.exists()) return;
  final target = p.normalize(run.absolute.path);
  final resolved = p.normalize(await run.resolveSymbolicLinks());
  final temporaryRoot = p.normalize(
    await Directory.systemTemp.resolveSymbolicLinks(),
  );
  if (!p.equals(target, resolved) ||
      !p.isWithin(temporaryRoot, resolved) ||
      !p.basename(resolved).startsWith('future-notes-validation-') ||
      p.basename(resolved) == 'future-notes-validation-') {
    throw StateError('Refusing cleanup outside an owned validation run.');
  }
  await Directory(resolved).delete(recursive: true);
}
