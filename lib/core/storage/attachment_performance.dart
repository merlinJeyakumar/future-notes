/// Per-computer adaptive limits. Memory is a ceiling, never an allocation goal.
class AttachmentPerformance {
  const AttachmentPerformance({
    this.targetPercent = 70,
    this.maxParallel = 0,
    this.memoryMiB = 0,
    this.checkBeforeOpen = false,
    this.verifyAfterOpen = false,
  });
  final int targetPercent;
  final int maxParallel;
  final int memoryMiB;
  final bool checkBeforeOpen;
  final bool verifyAfterOpen;
  static const defaults = AttachmentPerformance();

  factory AttachmentPerformance.fromJson(Object? value) {
    if (value == null) return defaults;
    if (value is! Map) {
      throw const FormatException('Invalid performance settings.');
    }
    final target = value['targetPercent'] ?? 70;
    final parallel = value['maxParallel'] ?? 0;
    final memory = value['memoryMiB'] ?? 0;
    final check = value['checkBeforeOpen'] ?? false;
    final verify = value['verifyAfterOpen'] ?? false;
    if (target is! int ||
        target < 10 ||
        target > 90 ||
        parallel is! int ||
        parallel < 0 ||
        parallel > 256 ||
        memory is! int ||
        (memory != 0 && (memory < 64 || memory > 65536)) ||
        check is! bool ||
        verify is! bool) {
      throw const FormatException('Invalid performance limits.');
    }
    return AttachmentPerformance(
      targetPercent: target,
      maxParallel: parallel,
      memoryMiB: memory,
      checkBeforeOpen: check,
      verifyAfterOpen: verify,
    );
  }
  Map<String, Object> toJson() => {
    'targetPercent': targetPercent,
    'maxParallel': maxParallel,
    'memoryMiB': memoryMiB,
    'checkBeforeOpen': checkBeforeOpen,
    'verifyAfterOpen': verifyAfterOpen,
  };
  AttachmentPerformance copyWith({
    int? targetPercent,
    int? maxParallel,
    int? memoryMiB,
    bool? checkBeforeOpen,
    bool? verifyAfterOpen,
  }) => AttachmentPerformance.fromJson({
    'targetPercent': targetPercent ?? this.targetPercent,
    'maxParallel': maxParallel ?? this.maxParallel,
    'memoryMiB': memoryMiB ?? this.memoryMiB,
    'checkBeforeOpen': checkBeforeOpen ?? this.checkBeforeOpen,
    'verifyAfterOpen': verifyAfterOpen ?? this.verifyAfterOpen,
  });
  @override
  bool operator ==(Object other) =>
      other is AttachmentPerformance &&
      targetPercent == other.targetPercent &&
      maxParallel == other.maxParallel &&
      memoryMiB == other.memoryMiB &&
      checkBeforeOpen == other.checkBeforeOpen &&
      verifyAfterOpen == other.verifyAfterOpen;
  @override
  int get hashCode => Object.hash(
    targetPercent,
    maxParallel,
    memoryMiB,
    checkBeforeOpen,
    verifyAfterOpen,
  );
}
