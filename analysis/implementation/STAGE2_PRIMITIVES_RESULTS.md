# Third Stage 2 revision/lease foundation results

The user approved [STAGE2_PRIMITIVES_VALIDATION.md](STAGE2_PRIMITIVES_VALIDATION.md)
including the retained analyzer exception. Branch/HEAD unchanged:
development/a9f6d247d7e27322d4afe542aa27240c72af031e.

| Check | Observed result |
| --- | --- |
| Offline dependency resolution | Exit 0; crypto remains 3.0.7, transitive to direct only |
| Formatter | Exit 0; two files formatted |
| Whitespace check | Exit 0; generated-file line-ending notices only |
| Non-mutating format check | Exit 0; two files, no changes |
| Focused foundation tests | Exit 0; all eight passed |
| Full suite | Exit 0; all 135 passed |
| Analyzer with approved flags | Exit 0; 95 diagnostics in 12.1s |
| Windows Debug build | Exit 0; executable built in 12.4s |
| Runtime | Not run |

Analysis has 93 informational lints, the original two unused-import warnings,
no errors. The three additions are initializing-formal style suggestions in
StorageRevision: explicit non-null constructor parameters initialize nullable
fields used by the missing revision. No new warnings. Full output:
[STAGE2_PRIMITIVES_ANALYSIS.txt](STAGE2_PRIMITIVES_ANALYSIS.txt).

Synthetic tests cover known SHA-256 digests, missing/empty distinction, same-size
content changes with restored mtime, 3 MiB bounded read callbacks, mid-read source
mutation, containment, independent settings/library ownership, duplicate lease
rejection/release/reuse and actual Windows file-handle contention. The latter
returned conflict before the external handle was unlocked. This is not an
independent-process or other-platform validation, and not a 4/10 GiB profile.

No project app was found before build; no executable was launched/stopped. Real
notes and settings were not accessed. These helpers have no production call sites;
the old direct writer remains unactivated against a real library.

The tested source/tests, manifests and Debug bundle are retained under
`.validation/future-notes-validation-stage2-primitives-a38000de30ae4c2f885d87241c618783`.
All 65 copied files match their source SHA-256 hashes. Earlier checkpoints remain.

Complete commit/recovery, expected-revision integration, baseline copies, journal
boundary interruption tests and writer-lease lifecycle publication remain pending.
Portable checked reads and renames cannot claim full power-loss atomicity or
protection against every hostile external filesystem change.
