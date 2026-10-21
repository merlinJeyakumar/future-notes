import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:path/path.dart' as p;

/// Limits apply to a read-only preview, never to attachment storage/export.
class OfficePreviewLimits {
  static const sourceBytes = 64 * 1024 * 1024;
  static const expandedBytes = 128 * 1024 * 1024;
  static const htmlBytes = 8 * 1024 * 1024;
  static const entries = 10000;
}

class DocumentPreviewException implements Exception {
  const DocumentPreviewException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All file and native handles are created and closed in this owned job.
/// The caller joins the job before deleting its cached input on lock/exit.
class OfficePreviewService {
  const OfficePreviewService({this.libraryPath});
  final String? libraryPath;

  Future<String> load(String path) {
    final dll =
        libraryPath ??
        officePreviewLibrary(
          operatingSystem: Platform.operatingSystem,
          executable: Platform.resolvedExecutable,
        );
    return Isolate.run(() => readOfficePreview(path, dll));
  }
}

String readOfficePreview(String path, String libraryPath) {
  validateOfficePreviewSource(path);
  final before = File(path).statSync();
  try {
    final library = libraryPath.isEmpty && (Platform.isIOS || Platform.isMacOS)
        ? DynamicLibrary.process()
        : DynamicLibrary.open(libraryPath);
    final open = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>, Pointer<Int32>),
          Pointer<Void> Function(Pointer<Utf8>, Pointer<Int32>)
        >('office_document_open');
    final free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('office_document_free');
    final convert = library
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Int32>),
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Int32>)
        >('office_document_to_html');
    final freeString = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('office_oxide_free_string');
    final nativePath = path.toNativeUtf8();
    final error = calloc<Int32>();
    Pointer<Void> document = nullptr;
    Pointer<Utf8> output = nullptr;
    try {
      document = open(nativePath, error);
      if (document == nullptr || error.value != 0) {
        throw const DocumentPreviewException(
          'Cannot preview this document. It may be damaged, password-protected or unsupported.',
        );
      }
      error.value = 0;
      output = convert(document, error);
      if (output == nullptr || error.value != 0) {
        throw const DocumentPreviewException('Document preview unavailable.');
      }
      // Do not copy an unbounded native string into Dart memory.
      final bytes = output.cast<Uint8>();
      var length = 0;
      while (length <= OfficePreviewLimits.htmlBytes && bytes[length] != 0) {
        length++;
      }
      if (length > OfficePreviewLimits.htmlBytes) {
        throw const DocumentPreviewException(
          'This document is too complex for the in-app preview. Open it in a system app.',
        );
      }
      final after = File(path).statSync();
      if (before.size != after.size || before.modified != after.modified) {
        throw const DocumentPreviewException(
          'The cached document changed. Open it again.',
        );
      }
      return sanitizeOfficePreview(output.toDartString(length: length));
    } finally {
      if (output != nullptr) freeString(output);
      if (document != nullptr) free(document);
      calloc.free(error);
      calloc.free(nativePath);
    }
  } on DocumentPreviewException {
    rethrow;
  } catch (_) {
    throw const DocumentPreviewException(
      'Document preview unavailable. Open it in a system app.',
    );
  }
}

/// Packaging contract: Apple links the C ABI into the application; Linux
/// installs its shared object beside Flutter's other native libraries.
String officePreviewLibrary({
  required String operatingSystem,
  required String executable,
}) => switch (operatingSystem) {
  'android' => 'liboffice_oxide.so',
  'ios' || 'macos' => '',
  'linux' => p.join(p.dirname(executable), 'lib', 'liboffice_oxide.so'),
  'windows' => p.join(p.dirname(executable), 'office_oxide.dll'),
  _ => throw UnsupportedError('Native Office preview is unavailable.'),
};

void validateOfficePreviewSource(String path) {
  final file = File(path);
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const DocumentPreviewException('The cached document is unavailable.');
  }
  final length = file.lengthSync();
  if (length == 0 || length > OfficePreviewLimits.sourceBytes) {
    throw const DocumentPreviewException(
      'This document is empty or too large for the in-app preview. Open it in a system app.',
    );
  }
  final extension = p.extension(path).toLowerCase();
  if (!{'.doc', '.docx', '.xls', '.xlsx'}.contains(extension)) {
    throw const DocumentPreviewException('Document format is not supported.');
  }
  if (extension == '.docx' || extension == '.xlsx') {
    _checkZipDirectory(file, length);
  }
}

/// Inspect bounded central-directory records without inflating XML/images.
void _checkZipDirectory(File file, int length) {
  final input = file.openSync();
  try {
    final tailSize = length < 65557 ? length : 65557;
    input.setPositionSync(length - tailSize);
    final tail = input.readSync(tailSize);
    final data = ByteData.sublistView(tail);
    var end = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50 &&
          i + 22 + data.getUint16(i + 20, Endian.little) == tail.length) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException();
    final count = data.getUint16(end + 10, Endian.little);
    final size = data.getUint32(end + 12, Endian.little);
    final offset = data.getUint32(end + 16, Endian.little);
    if (data.getUint32(end + 4, Endian.little) != 0 ||
        count != data.getUint16(end + 8, Endian.little) ||
        count > OfficePreviewLimits.entries ||
        count == 0xffff ||
        size > 4 * 1024 * 1024 ||
        offset + size != length - tailSize + end) {
      throw const FormatException();
    }
    var position = offset;
    var expanded = 0;
    for (var i = 0; i < count; i++) {
      if (position + 46 > offset + size) throw const FormatException();
      input.setPositionSync(position);
      final header = input.readSync(46);
      if (header.length != 46) throw const FormatException();
      final record = ByteData.sublistView(header);
      if (record.getUint32(0, Endian.little) != 0x02014b50) {
        throw const FormatException();
      }
      final entrySize = record.getUint32(24, Endian.little);
      expanded += entrySize;
      if (entrySize > 32 * 1024 * 1024 ||
          expanded > OfficePreviewLimits.expandedBytes ||
          record.getUint16(28, Endian.little) > 4096 ||
          record.getUint16(8, Endian.little) & 1 != 0) {
        throw const FormatException();
      }
      position +=
          46 +
          record.getUint16(28, Endian.little) +
          record.getUint16(30, Endian.little) +
          record.getUint16(32, Endian.little);
    }
    if (position != offset + size) throw const FormatException();
  } catch (_) {
    throw const DocumentPreviewException(
      'This document is damaged, encrypted or too complex for the in-app preview. Open it in a system app.',
    );
  } finally {
    input.closeSync();
  }
}

/// Only passive text, tables and bounded formatting enter the Flutter renderer.
/// No browser, script, embedded object, external image or link is activated.
String sanitizeOfficePreview(String source) {
  final document = html.parse(source);
  const allowed = {
    'html',
    'body',
    'div',
    'span',
    'p',
    'br',
    'hr',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'sub',
    'sup',
    'ul',
    'ol',
    'li',
    'table',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'td',
    'th',
    'caption',
    'blockquote',
    'pre',
    'code',
  };
  final elements = document.querySelectorAll('*');
  if (elements.length > 50000) {
    throw const DocumentPreviewException(
      'This document is too complex for the in-app preview.',
    );
  }
  for (final element in elements.reversed) {
    if (!allowed.contains(element.localName)) {
      if ({
        'head',
        'script',
        'style',
        'iframe',
        'object',
        'embed',
        'svg',
        'math',
        'img',
      }.contains(element.localName)) {
        element.remove();
      } else {
        element.replaceWith(dom.Text(element.text));
      }
      continue;
    }
    final oldStyle = element.attributes['style'];
    final span = element.attributes['colspan'];
    final rowSpan = element.attributes['rowspan'];
    element.attributes.clear();
    if (span != null &&
        (int.tryParse(span) ?? 0) > 0 &&
        (int.tryParse(span) ?? 0) <= 100) {
      element.attributes['colspan'] = span;
    }
    if (rowSpan != null &&
        (int.tryParse(rowSpan) ?? 0) > 0 &&
        (int.tryParse(rowSpan) ?? 0) <= 100) {
      element.attributes['rowspan'] = rowSpan;
    }
    if (oldStyle != null) {
      final safe = <String>[];
      for (final declaration in oldStyle.split(';')) {
        final pair = declaration.split(':');
        if (pair.length != 2) continue;
        final key = pair[0].trim().toLowerCase();
        final value = pair[1].trim().toLowerCase();
        if ({
              'text-align',
              'font-weight',
              'font-style',
              'text-decoration',
              'vertical-align',
            }.contains(key) &&
            RegExp(r'^[a-z0-9 -]{1,30}$').hasMatch(value)) {
          safe.add('$key:$value');
        }
      }
      if (safe.isNotEmpty) element.attributes['style'] = safe.join(';');
    }
  }
  // Derived presentation metadata only; source cell contents/header roles stay
  // untouched. Annotate in one pass rather than scanning siblings per UI row.
  for (final parent in document.querySelectorAll('table,thead,tbody,tfoot')) {
    var index = 0;
    for (final row in parent.children.where((e) => e.localName == 'tr')) {
      row.attributes['data-preview-row'] = '${index++ % 2}';
    }
  }
  return document.body?.innerHtml ?? '';
}
