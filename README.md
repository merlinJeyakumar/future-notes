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
The Intel Mac Monterey workflows accepted for this release are listed in
`scripts/release/RELEASE_NOTES.md`. iOS application/
device and Linux native acceptance remain pending. A universal binary alone
does not establish Apple Silicon runtime acceptance.

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

## Approved Apple compatibility build

The release's tested Monterey Mac uses the separate `v1.4.4-apple-compat` source
tag and `codex/apple-monterey-compat` branch, pinned to Flutter `3.38.3`, framework
`19074d12f7eaf6a8180cd4036a430c1d76de904e` and Dart `3.10.1`. Keep its own lock and
tooltip adaptation. This exception does not downgrade the canonical Windows/
Android pins above. The two source tags and each downloadable artifact are
recorded in `release-provenance.json`; iOS native/device validation stays pending.
