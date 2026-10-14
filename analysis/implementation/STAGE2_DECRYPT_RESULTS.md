# Second Stage 2 typed-decryption results

The user approved the exact gate and analyzer exception in
[STAGE2_DECRYPT_VALIDATION.md](STAGE2_DECRYPT_VALIDATION.md).
Branch/HEAD remain development/a9f6d247d7e27322d4afe542aa27240c72af031e.

| Check | Result |
| --- | --- |
| Formatter | Exit 0; 9 files, 8 formatted |
| Whitespace check | Exit 0; generated-file line-ending notices only |
| Non-mutating format check | Exit 0; 9 files, 0 changes |
| Focused tests | Exit 0; all 88 passed |
| Full suite | Exit 0; all 127 passed |
| Analyzer with approved flags | Exit 0; 92 diagnostics in 14.8s |
| Windows Debug build | Exit 0; executable built in 12.6s |
| Runtime | Not run |

Analysis contains 90 info, the original two unused-import warnings, no errors.
The only additions versus the codec gate are two informational brace lints in
the synthetic cipher harness. No new warning/error. Full output:
[STAGE2_DECRYPT_ANALYSIS.txt](STAGE2_DECRYPT_ANALYSIS.txt).

The 14 new regressions passed: 11 installed-cipher fixtures and three controlled
editor/preview tests. Valid empty string/app/binary payloads remain distinct from
failure; successful empty decryption avoids fallback. Failure-prefix content,
legacy key-derived IVs and default-key fallback remain readable. Malformed
framing, invalid padding, aligned truncation and a fixed wrong-password fixture
produce no payload. Failed previews are not cached; valid empty previews are.

These tests do not establish authenticated integrity, universal wrong-key
rejection or large-file memory behavior. Buffered package/protection adapters,
empty encryption, recoverable persistence and runtime gates remain pending.
R06 is partially implemented, not closed across every consumer.

No project application was found before building. No app was launched/stopped.
No real notes, passwords or keys were read. No encryption writer, format,
dependency version, branch, commit or push changed in this candidate.

Tested source/tests, manifests and Debug runtime are retained in
`.validation/future-notes-validation-stage2-decrypt-784efd77c4084df482059b2aae0f99a6`.
All 63 copied files match their source SHA-256 hashes. Earlier checkpoints remain.
Real-library activation stays withheld until the persistence and operation
safety stages and isolated runtime gates pass.
