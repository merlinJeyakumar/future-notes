# First Stage 2 codec gate results

The user approved the exact sequence in [STAGE2_CODEC_VALIDATION.md](STAGE2_CODEC_VALIDATION.md),
including the retained analyzer baseline exception. Branch: development;
HEAD: a9f6d247d7e27322d4afe542aa27240c72af031e. No application launch.

| Check | Observed result |
| --- | --- |
| Formatter | Exit 0; 7 files, 6 formatted |
| `git diff --check` | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; 7 files, 0 changes |
| Focused storage, VM and draft dialog tests | Exit 0; all 74 passed |
| Full test suite | Exit 0; all 113 passed |
| Analyzer with approved exception | Exit 0; 90 diagnostics in 39.4s |
| Windows Debug build | Exit 0; built executable in 18.4s |
| Runtime | Not run |

Analysis has 88 informational lints, the same two unused-import warnings and
no errors. Compared with the transition baseline, two informational diagnostics
were removed and none were added. This is not clean analysis. Full output is
retained in [STAGE2_CODEC_ANALYSIS.txt](STAGE2_CODEC_ANALYSIS.txt).

The 13 new regressions cover independent envelope recognition, immutable unknown
metadata, IDs/timestamps, legacy attachment representation, exact body strings,
malformed schemas, sync/async agreement, package metadata round trips and synthetic
discovery without rewriting files. An out-of-display-range timestamp stays intact
and does not hide the note. Tests use synthetic fixtures and checked disposable
directories; existing tests retain a throwing production-path resolver.

No project application was found before compilation. No executable was launched
or terminated. UserData and the opaque root note were not accessed. No dependency,
cipher, KDF, wire-format, branch, commit or push change occurred in this gate.

The tested source/tests, manifests and Debug runtime bundle are retained under
`.validation/future-notes-validation-stage2-codec-8c472a31d75d454898ef508322c8a35c`.
All 61 copied files were SHA-256 checked against their sources. Previous
checkpoints remain available; no notes were copied.

This gate establishes tested codec and metadata compatibility for synthetic
fixtures. Recoverable commits, leases, expected revisions, typed decrypt results,
complete streaming packages and platform/runtime/performance gates remain pending.
It does not authorize real-library activation or establish backup completeness.
