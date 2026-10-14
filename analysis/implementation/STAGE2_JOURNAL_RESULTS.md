# Fourth Stage 2 journal-schema results

The user approved the exact [journal gate](STAGE2_JOURNAL_VALIDATION.md), including
the analyzer exception. Branch/HEAD unchanged:
development/a9f6d247d7e27322d4afe542aa27240c72af031e.

| Check | Result |
| --- | --- |
| Formatter | Exit 0; two files formatted |
| Whitespace check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; two files, no changes |
| Focused journal tests | Exit 0; all ten passed |
| Full suite | Exit 0; all 145 passed |
| Analyzer with approved flags | Exit 0; 97 diagnostics in 11.6s |
| Windows Debug build | Exit 0; executable built in 8.9s |
| Runtime | Not run |

Analysis has 95 informational lints, the original two unused-import warnings,
no errors. The two new informational diagnostics are a constructor guard brace
and test string interpolation. Full output: [STAGE2_JOURNAL_ANALYSIS.txt](STAGE2_JOURNAL_ANALYSIS.txt).

Ten pure codec tests passed for canonical intents/receipts, expected/staged
revisions, absence versus empty payload, constrained derived paths, malformed
identities/metadata, traversal/device/stream aliases, unknown versions/fields,
duplicate/noncanonical keys, bounded metadata and exact receipt binding.
These tests perform no filesystem commit or restoration and do not establish
crash recovery, durability or protection against adversarial journal forgery.

No project app was found before the build. No executable was launched/stopped;
real notes/settings were not accessed. No dependency versions changed. The
previous checkpoints remain available, and real-library activation is withheld.

The validated source/tests, manifests and Windows Debug bundle are retained at
`.validation/future-notes-validation-stage2-journal-3a4ea054669a4e33bde8025275c954b0`.
All 67 copied files were SHA-256 verified against their source. No notes were
copied, and earlier checkpoints remain available.

Filesystem commit/recovery, baseline retention, unexpected external-change
handling, lease lifecycle integration and boundary interruption tests remain
pending. The current direct writer is not connected to these journal types.
