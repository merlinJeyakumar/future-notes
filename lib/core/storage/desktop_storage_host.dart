import 'dart:io';

/// Host eligibility only. RecoverableStore still acquires ownership and admits
/// the actual filesystem before reading journals or exposing a writable root.
bool get isOwnedDesktopHost =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
