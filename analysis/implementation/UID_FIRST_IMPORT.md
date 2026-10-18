# Metadata-first UID decisions on package import

Implemented 2026-10-18 in the shared transactional importer used by Windows and mobile document-provider libraries.

## Behavior and compatibility

Read bounded note metadata before extracting attachment payloads. Binary packages expose their leading metadata; ZIP/ZIP64 packages extract only `note.json` during review, using the existing stored/strict DEFLATE parser. Archive passwords decrypt this bounded metadata, not the attachment entries.

Matching UIDs use the existing Duplicate / Back up & Replace / Ignore presentation. Ignore returns before attachment extraction and removes temporary review metadata. Duplicate and Replace then run the established full import, preserving strict CRC/DEFLATE/framing checks, mention identities, unknown metadata, encryption/package versions, attachment-first publication, predecessor backups, cancellation and progress. No settings or platform presentation were redesigned.

The reviewed source is guarded by its path, length and filesystem modification/change metadata before extraction; the extracted note metadata must match the reviewed metadata before publication. These are bounded metadata checks, not full-file checksum scans. Optional verification policy remains unchanged. Provider source acquisition may still require a necessary initial copy; this change makes no zero-copy guarantee for every provider.

## Validation

- 193 distinct affected host tests pass. Coverage includes all four binary/ZIP password combinations, Ignore without staged attachments, UID identity/unknown fields, source changes during the decision, duplicate/replacement backups, cancellation, strict legacy DEFLATE, provider publication/recovery, editing and the accepted Windows short-path cache fix.
- One new corruption test initially expected a specific decoder exception from random damaged DEFLATE bytes. The fixture was made deterministic by changing the declared attachment CRC consistently across ZIP framing. Metadata review succeeds; full extraction rejects the CRC after proceeding. The focused correction passed; already-passing files were not repeated.
- Scoped analysis has zero errors/warnings; informational lints remain. Formatting and whitespace checks passed.
- Obfuscated Windows release probe: four password/format Ignore choices occurred without staged attachments; Duplicate and Replace succeeded. Existing legacy ciphertext/open/cache/revocation and check-setting combinations also passed. Probe data lived in a disposable library, never the user's library.
- LG LM-G900 Android 12 release probe: four format/password metadata reviews through retained SAF descriptors succeeded, with no extracted attachment files before choices. All three duplicate outcomes passed; existing payload read attempts were zero. Native copy decryption, saving progress, finishing state and synthetic provider cleanup passed. Temporary probe installation was followed by restoration of the accepted normal Preview without clearing data. Unrelated speed benchmarks were skipped.

## Delivery and platform bounds

Normal protected Windows and Android Preview candidates are built from `lib/main.dart`, not the diagnostic entry points. Accepted bundles/APK are preserved under `.validation/uid-preflight-accepted/`. Artifact, hardening, packaging and startup evidence use the `.validation/uid-preflight-*` prefix.

Final Windows build passed in 49.7 seconds; runner hardening checks passed. Its normal window appeared in 2129 ms and remained responsive for 20 seconds, with zero fatal/layout matches and working set 170516480 bytes. No app input or note edits were sent.

Final Android build passed in 79.8 seconds. APK SHA-256: `503acc3bd1c72bbb1f81591151707947199cbd8d8ea5c14e7f8a56cec5e97050`. All 18 native libraries passed the existing ELF inspection and 16 KiB APK alignment checks. Data-preserving streaming installation succeeded. Cold launch took 1398 ms; the PID remained stable for 20 seconds, foreground/resumed with no keyguard and zero fatal/layout errors. PSS was 139158 KiB. Screenshot inspection confirmed the normal notes list, not the probe screen. The user confirmed the duplicate-import check after delivery.

iOS uses the same provider import coordinator and metadata API; Mac/Xcode and iOS device validation remain deferred at the user's direction. Other platform runner directories and legacy fallback readers are not evidence of transactional-import runtime support; macOS/Linux/browser runtime coverage is not established by these checks. No unsupported workflow was silently enabled.

The user subsequently confirmed the final normal-app check: duplicate options appear before attachment extraction, and Ignore works as expected. This manual acceptance is separate from the synthetic automated probes.

The accepted Windows cache correction remains in place. Notes, `D:\tools`, portable releases and existing tags are preserved. The user authorized validation, commit and push after acceptance; release publication is not included.
