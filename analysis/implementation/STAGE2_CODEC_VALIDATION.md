# First Stage 2 codec candidate validation

Status: approved and passed on 2026-10-13. All 74 focused tests, all 113 tests
and Windows Debug compilation passed. Analysis retained the original two
warnings with no new diagnostics. See [STAGE2_CODEC_RESULTS.md](STAGE2_CODEC_RESULTS.md).

Run from `D:\Project\NativeDevps\future-notes`:

```powershell
$stage2CodecPaths = @(
  'lib/features/dashboard/models/draft_session.dart',
  'lib/features/dashboard/models/note_envelope.dart',
  'lib/features/dashboard/services/note_codec.dart',
  'lib/features/dashboard/services/background_service.dart',
  'lib/features/dashboard/services/pack_service.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'test/storage/note_codec_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @stage2CodecPaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage2CodecPaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage test/viewmodels test/draft_decision_dialog_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Execute sequentially and inspect every result; stop on a failed required check
or unexpected new analyzer warning/error. Inspect informational deltas too.
The user approved retaining the existing analysis exception for this candidate.
The transition baseline has 92 diagnostics (90 info, two unused-import warnings,
zero errors). No dependencies changed; no pub get or upgrade is required.

Expected registration counts: 74 focused tests and 113 full-suite tests. These
are not passing results. Codec tests use the synthetic Stage 0 fixtures and
operation-owned temp directories with checked cleanup. No real notes or native
picker are involved. Existing isolation regressions retain the throwing
production-directory resolver.

Before the build, check for a project application; do not launch or terminate one.
Retain previous source/executable checkpoints. No app launch is included.

This gate covers the codec, metadata compatibility, synthetic discovery reads
and compilation. It does not validate recovery commits, body/attachment decrypt
result redesign, complete exports, bounded packages, actual Windows exit, or
platform/performance behavior. Real-library activation remains withheld.
