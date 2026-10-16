/// Internal resources are opaque identities, never file paths or system URLs.
enum FnotesResource { attachment, unsupported }

class FnotesTarget {
  const FnotesTarget(this.resource, this.id);
  final FnotesResource resource;
  final String id;

  static bool isInternal(String value) =>
      value.trimLeft().toLowerCase().startsWith('fnotes:');

  static FnotesTarget? parse(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'fnotes' ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.host.isEmpty ||
          uri.pathSegments.length != 1 ||
          uri.pathSegments.single.isEmpty ||
          uri.pathSegments.single.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        return null;
      }
      return FnotesTarget(
        uri.host == 'attachment'
            ? FnotesResource.attachment
            : FnotesResource.unsupported,
        uri.pathSegments.single,
      );
    } on FormatException {
      return null;
    }
  }

  static String attachment(String id) =>
      'fnotes://attachment/${Uri.encodeComponent(id)}';

  /// Returning null keeps the converter's normal URL sanitization in charge.
  static String? sanitize(String value) {
    final target = parse(value);
    return target?.resource == FnotesResource.attachment
        ? attachment(target!.id)
        : null;
  }
}
