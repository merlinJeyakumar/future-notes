/// Presentation-selected scheduling; storage and explicit Save keep their
/// existing acknowledgement and recovery contracts on every platform.
class AutoSavePolicy {
  const AutoSavePolicy({
    this.idleDelay = const Duration(seconds: 2),
    this.minimumInterval = Duration.zero,
    this.deferDuringWork = false,
  });

  static const desktop = AutoSavePolicy();
  static const mobile = AutoSavePolicy(
    idleDelay: Duration(seconds: 15),
    minimumInterval: Duration(seconds: 30),
    deferDuringWork: true,
  );

  final Duration idleDelay;
  final Duration minimumInterval;
  final bool deferDuringWork;
}
