# Future Notes

A local-first Flutter notes application. The Dart package name remains
`flutter_application_1` for compatibility with existing imports.

## Toolchain baseline

Use the pinned Flutter SDK before resolving dependencies, analyzing, testing or
building. `.flutter-version` records the release; the complete baseline is:

| Component | Pinned value |
| --- | --- |
| Flutter | `3.41.5` (stable) |
| Framework revision | `2c9eb20739dfec95e2c74bd3dfa4601b0a8a36aa` |
| Bundled Dart | `3.11.3` |

Run `flutter --version --machine` and check `frameworkVersion`,
`frameworkRevision` and `dartSdkVersion` against this table. Configure the same
SDK in the editor and on build hosts; do not substitute an older SDK or temporary
API shims. The resolved lock requires Dart `>=3.11.0`; the package SDK constraint
now reflects that floor. The exact build baseline remains Dart `3.11.3`.

Keep `pubspec.lock` and the pinned dependency versions unchanged when setting up
a host:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Use scoped analysis/tests when validating a bounded change. Read `RULESBOOK.md`
before executing builds or runtime checks. This SDK pin is a reproducibility
baseline; it does not establish native platform support. macOS/iOS still require
their compatible Xcode/CocoaPods and actual host/device gates. Linux requires a
native GUI/build host. Preserve accepted Windows and Android builds until their
replacements pass the affected validation gates.

## Native desktop setup status

The staged implementation and its current evidence are recorded in
[the implementation status](analysis/multiplatform-gap-review-2026-10-21/implementation-status.md).
macOS, Linux and iOS native acceptance remains pending; Windows-host contract
tests do not replace those checks.

On the destination macOS or GNU/glibc Linux host, first use the pinned Flutter
SDK and install the host's Flutter native prerequisites, Rust and build tools.
Build the pinned desktop Office engine before building the application:

```sh
bash tools/build-desktop-office.sh
flutter pub get --enforce-lockfile
```

The recipe refuses to overwrite an existing Office artifact. Preserve an
accepted artifact before preparing a replacement. On macOS, resolve the app's
Pods with CocoaPods in `macos`, then build with `flutter build macos --release`.
On Linux use `flutter build linux --release`. Run each only on its native host;
native signing, permissions, portal integration and preview acceptance remain
separate gates. iOS uses the existing mobile Office recipe and requires its own
Mac/Xcode, signing and device validation.
