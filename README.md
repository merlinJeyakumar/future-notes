# Future Notes

A local-first Flutter notes application. The Dart package name remains
`flutter_application_1` for compatibility with existing imports.

## Toolchain baseline

The `codex/apple-monterey-compat` branch uses a separate Apple compatibility
baseline for the current Intel Mac running macOS Monterey. Before resolving
dependencies, analyzing, testing or building this branch, use:

| Component | Apple/Monterey value |
| --- | --- |
| Flutter | `3.38.3` |
| Framework revision | `19074d12f7eaf6a8180cd4036a430c1d76de904e` |
| Bundled Dart | `3.10.1` |

Run `flutter --version --machine` and check `frameworkVersion`,
`frameworkRevision` and `dartSdkVersion` against this table. `.flutter-version`
records this branch-specific Flutter release, and the package SDK constraint
allows its bundled Dart SDK.

The accepted Windows/Android parent branch remains pinned separately to Flutter
`3.41.5`, framework revision
`2c9eb20739dfec95e2c74bd3dfa4601b0a8a36aa`, and Dart `3.11.3`. This Apple
compatibility branch does not change that accepted baseline.

Keep `pubspec.lock` and the pinned dependency versions unchanged after resolving
the approved Apple compatibility lock on this branch:

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
The selected Intel Mac Monterey workflows are accepted as listed in
`scripts/release/RELEASE_NOTES.md`. iOS application/device and Linux native
acceptance remain pending; universal packaging alone does not validate ARM runtime.

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

## Release provenance

`v1.4.4-apple-compat` identifies this approved Mac compatibility source for
version `1.4.4+11`; `v1.4.4` identifies the canonical development release with
the separately preserved Windows/Android pins. Functional fixes are aligned,
and `release-provenance.json` records exact platform source/artifact hashes.
