# Attachment cache lifetime

The user accepted the off-by-default opening scans and requested retaining the
decrypted file until note lock or application Exit.

## Finding and correction

The existing file cache already reused completed entries and did not delete
them when a viewer closed or ordinary navigation occurred. Its key includes the
note identity, attachment ID and credential generation. A successful password
change incremented that generation, but note loading reset the editor generation
to zero. Returning to the same unlocked note could therefore miss a valid entry
and decrypt again even though its prior cached file was still retained.

The view model now remembers the acknowledged credential generation per canonical
note path for this process. Loading restores both the session and persisted-body
baseline to that generation. Successful mutation acknowledgement updates it;
imported replacement resets it after the existing cache invalidation. No password
or key bytes are added to this map, and it is not persisted to disk.

Typing, Save, viewer closure and navigation retain completed cached files.
Explicit lock, password changes, removal, replacement and Delete still invalidate
affected entries. Actual Exit removes cached files across every unlocked note.
Existing deferred cleanup for files held by external applications is unchanged.
Missing/modified cached files are still re-prepared rather than blindly reused.
No note, encryption, settings or cache-directory format changes are introduced.

## Validation

- Formatting and whitespace checks passed for the two changed files.
- Full analysis completed with 112 diagnostics, including one unused-import
  warning in unchanged test/file_details_dialog_test.dart. That file matches
  HEAD and was not edited. Scoped analysis of both changed files reported zero
  errors/warnings and 26 existing informational diagnostics.
- One combined affected synthetic suite passed all 80 tests: cache service,
  cache lifecycle, owned mutations, draft transitions and session safety.
- The expanded lifecycle regression verifies unchanged cache path and zero new
  decryptions after protection changes, navigation, typing and Save; it also
  verifies lock/rekey/removal/Delete invalidation. A new two-note case verifies
  that closing the cache removes both notes' plaintext files.

Evidence prefix: .validation/attachment-cache-retention-. One protected canonical
Windows Release build passed in 45.0 seconds. Private symbols/map and runner
ASLR, high-entropy ASLR, DEP, CFG, stack-cookie and restricted DLL-loading checks
passed. The existing CMake FetchContent deprecation remains. The prior accepted
bundle is retained in .validation/attachment-cache-retention-previous-release,
with verified EXE/AOT hash equality before compilation.

The candidate launched once as PID 60708 with a visible responsive window and
clean protection/media-registration logs. All four observations across 15 seconds
remained responsive; working set ranged from 157.9 to 290.3 MiB during that window.
This is startup observation, not a cache-throughput benchmark.

On 16 October 2026 the user answered "perfect" to the repeat-open, navigation and
lock/unlock check, then requested committing and pushing the correction. Manual
acceptance passed. The existing automated test/build results are retained without
duplicate execution because application code has not changed since validation.

Notes, published releases, tags and unrelated changes remain preserved. Delivery
is limited to the correction, its regressions and this validation report on
development; no release publication or tag change is included.
