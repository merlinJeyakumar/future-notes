# Sixth Stage 2 recoverable-backend results

The user approved the exact [backend gate](STAGE2_RECOVERY_VALIDATION.md),
including the analyzer exception. Branch/HEAD unchanged:
development/a9f6d247d7e27322d4afe542aa27240c72af031e.

| Check | Result |
| --- | --- |
| Formatter | Exit 0; two files formatted |
| Whitespace check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; two files, no changes |
| Focused backend tests | Exit 0; all 46 passed |
| Full suite | Exit 0; all 199 passed |
| Analyzer with approved flags | Exit 0; 98 diagnostics in 10.9s |
| Windows Debug build | Exit 0; executable built in 9.1s |
| Application runtime | Not run |

Analysis retained exactly the previous 96 informational lints and original two
unused-import warnings, with no errors or diagnostic additions/removals. Output:
[STAGE2_RECOVERY_ANALYSIS.txt](STAGE2_RECOVERY_ANALYSIS.txt).

Windows synthetic-file tests passed for 18 injected commit boundaries, three
recovery boundaries and native failures before/after movement. They verified
exact first-baseline/prior-version retention, repeatable recovery, absent/empty
targets, optimistic conflicts, one queue and independent leases, cancellation,
source/external changes, damaged/oversized/orphan metadata, identity collisions
and a multi-window file-backed hash round trip.

Partial baselines or damaged receipts remained non-writable with active bytes
retained. Unexpected external objects were preserved rather than restored over.
Historical completion receipts did not resurrect a later missing active file.
Valid completion receipts survived failures after receipt writing; those Save
calls still reported recovery-required rather than claiming acknowledgement.

The tested source/tests, manifests and Debug bundle are retained under
`.validation/future-notes-validation-stage2-recovery-b4823428c61442cc8ebdae767cc0e7cf`.
All 71 copied files were SHA-256 verified against their source. Earlier
checkpoints remain available. No notes were copied.

These hooks simulate interruption with handle cleanup, not abrupt process death
or power failure. Portable flush/rename is recoverable replacement, not complete
power-loss atomicity. File containment/create-reopen checks cannot exclude
hostile concurrent filesystem replacement. Large-history paging, worker dispatch,
application file/settings adoption, discovery ordering and UI/runtime remain
pending. No finding is closed by this backend gate.

No project app was found before the build. No executable was launched/stopped;
real notes/settings were not accessed and no dependency versions changed.
Production environments are rejected by this backend before I/O. Real-library
activation remains withheld.
