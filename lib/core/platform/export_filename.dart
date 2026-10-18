import 'dart:convert';

/// Portable suggested filename. The native picker still lets the user rename it.
String noteExportFileName(String title, String extension) {
  if (extension != 'fnote' && extension != 'zip') {
    throw ArgumentError.value(extension, 'extension');
  }
  var name = title
      .replaceAll(
        RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]'),
        ' ',
      )
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\.(fnote|zip)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (name.isEmpty) name = 'Untitled note';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(name)) {
    name = 'Note - $name';
  }
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in name.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (bytes + length > 180) break;
    result.write(character);
    bytes += length;
  }
  return '${result.toString().replaceAll(RegExp(r'[.\s]+$'), '')}.$extension';
}
