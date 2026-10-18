# Windows attachment cache correction

## Failure and cause

After development commit `76b2a61`, the user reported every Windows attachment opening failed, including newly attached files. The first synthetic tests and compiled release probe passed, but did not cover the affected cache-path representation. The failure was not initially reproduced; those passes did not validate the user's path.

A normal protected candidate recorded content-free diagnostic code `category=input reason=1 os_code=0`: the newly added owned-output lease rejected the cache destination before decryption. A Windows short-path alias reproduced the same guard failure and exact user-facing error in a new regression test. No user note payload was inspected or changed during diagnosis.

## Correction and preserved behavior

Restore the pre-`76b2a61` Windows viewer-cache transform path by omitting the publication output lease for this decrypt-only destination. Viewer files are not adopted into library publication; the existing cache manifest, private directory, path checks, exclusive file creation, cancellation, cleanup and lock revocation continue to own them. Optional source/output checks still follow saved settings.

The change is guarded by `Platform.isWindows`; Android's cache lease path is unchanged. Storage publication, encrypted formats, passwords, source attachments and cache lifetime are unchanged. Numeric Windows failure codes were added without paths, filenames, exception text, content or credentials. `RULESBOOK.md` now explicitly locks accepted platform code, features, designs and bug fixes during other-platform work.

## Validation

- The new Windows short-path regression failed before the correction with `Attachment decryption could not be completed` and reason 1; it passes afterward, including exact plaintext, immediate cache reuse and invalidation/removal.
- Combined cache, lifecycle, worker-budget and cipher suite: 53 tests passed. Scoped analysis: no errors/warnings; informational lints remain. Formatting/whitespace passed.
- Before the correction, an obfuscated Windows release probe passed six legacy encrypted fixtures (15 bytes, 448706 bytes and 1048593 bytes, default key and synthetic password), direct/worker/cache paths, reuse/revocation, and the actual Save/Attach/Open owned-storage flow with all four source/output-check combinations. These baseline passes explain why additional path-specific coverage was necessary, rather than establishing that no regression existed.
- Corrected protected Windows build passed in 48.9 seconds, with ASLR, high-entropy ASLR, DEP, CFG, stack cookie and dependent-load hardening checks passing. Normal app startup created a responsive window in 1587 ms; it remained responsive for 20 seconds with zero fatal/layout matches and zero attachment failure codes before manual retries. Working set was 166879232 bytes. Evidence is recorded under `.validation/desktop-decrypt-fixed-*`. The user subsequently confirmed attachment opening in the corrected normal app.

The user subsequently confirmed attachment opening works in the corrected normal Windows app. This manual acceptance is separate from the synthetic probes.

Previous Windows bundles were preserved under `.validation/desktop-decrypt-before/` and `.validation/desktop-decrypt-diagnostic/`. `D:\tools`, notes, published releases and tags are unchanged. The user later authorized committing and pushing this accepted correction together with metadata-first import. Android runtime was not repeated for the Windows-only branch; iOS/macOS validation remains deferred.
