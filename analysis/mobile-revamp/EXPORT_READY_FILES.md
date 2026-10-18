# Mobile note export: ready file, native actions and reuse

## Changes

- Note-package export prepares a private owned file and finishes the job without
  opening a chooser. Export ready offers Save, Share and Close. Save/Share leave
  the result dialog mounted; cancelled/failed actions retain the file for retry.
  Hiding preparation presents the ready result on completion when the dashboard
  route is current, without replacing another modal.
- Android Save uses ACTION_CREATE_DOCUMENT and a bounded 256 KiB stream from
  the prepared file to the granted content URI. UI receives only byte counts,
  shows actual transfer progress, and prevents concurrent actions. Short/source
  changes and I/O failures are rejected; the prepared source stays available.
- Android Share grants read-only FileProvider access to that exact prepared file
  in a dedicated cache subtree. It does not repack or copy a large package into
  a second share cache. Existing attachment export actions are unchanged.
- Completed note packages are reused when note metadata, attachment length/time
  fingerprints, format, archive password and verification options match. This
  performs metadata checks rather than another payload transform/scan. The key
  is a process-secret HMAC; passwords/hashes are not written to settings/journals.
- One prepared package per note is retained. A successful replacement removes
  its predecessor; lock/credential invalidation/removal/exit clear the relevant
  cache. Missing or changed cached files regenerate. Owned orphan directories
  are cleaned at the next cache initialization after process termination.
- Canonical private roots and ownership guards remain enforced. Picked files are
  never adopted. Existing note/package formats and Windows presentation remain
  unchanged. Saved external files are user-chosen outputs, not library storage.
- iOS source adapters use its native Files export picker and activity sheet.
  Mac/Xcode and iPhone/iPad validation remain deferred; no iOS runtime claim.

## Design

Stitch Pro unavailable; disclosed Flash fallback using the existing theme.
Reference d1f4497e3ddd4906a7cfbbeda4046fb3; saved under
.stitch/designs/mobile-export-ready.html and .png. Extra generated verification
claims/cancel-write controls were not adopted.

## Validation

- Combined affected suite: all 18 passed. Includes retained dialog, no automatic
  chooser, changing native save bytes/percent, disabled duplicate actions,
  cancelled/failed/successful Save retries, same prepared path used for Share,
  and explicit Close with cached file retained. Existing result lifecycle,
  navigation, password and temporary-directory alias tests passed.
- Real owned-storage package cache integration passed: unchanged inputs reused
  the same object/file; body edits, format/password changes, absent cached file
  and lock required regeneration or revocation. A focused final run also passed
  attachment-source timestamp invalidation. No default verification was enabled.
- Scoped analysis: zero errors/warnings; 72 informational lints in the existing
  scope. Formatting/whitespace passed. Desktop presentation diff empty.
- Evidence: .validation/mobile-export-ready-tests.txt,
  .validation/mobile-export-ready-cache-final.txt,
  .validation/mobile-export-ready-analysis.txt.

## Delivery

Accepted pre-change APK retained at
.validation/mobile-export-ready-accepted/app-preview-release.apk, SHA-256
4e5f0c6b8023a0a681accf09c2f302fed841b88ab181a4953d92264827c13d3e.
Protected Android build passed in 68.9 seconds. APK SHA-256:
b9da4430bdc04d6abe44e7d9a0a36ab0954892aaf5638d1d8c9a5b1d755cc44c.
Private symbol assertions, inspection of 18 native libraries with 16 KiB
alignment for 64-bit ELF loads, and zipalign passed. Staged in-place install
succeeded. Cold activity launch took 1,195 ms; process 15130 stayed stable and
resumed for 20 seconds with zero fatal/layout log matches, keyguard absent,
observed total PSS 172,779 KiB (not a peak/stress measurement).
Evidence: .validation/mobile-export-ready-build.txt,
.validation/mobile-export-ready-packaging.json,
.validation/mobile-export-ready-startup.json.

Actual Android picker/share acceptance and large-file save transfer remain
manual checks. No real save destination or share target was selected by the
agent. iOS builds/device checks remain deferred. No commit, push, release or
tag change is included; notes, portable releases and prior APK remain preserved.
