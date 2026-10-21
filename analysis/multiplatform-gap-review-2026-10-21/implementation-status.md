# Staged implementation and validation

Updated 2026-10-21. Baseline: development `a5be98cd520d501eb8f31e19bacb7bcd4cc8f4e6`, version `1.4.3+10`, plus the recorded pre-existing dirty worktree. The earlier analysis describes the starting state; this document records the subsequent implementation. **Native macOS/Linux/iOS support is not yet accepted.** Source and mocked contracts do not establish native compilation or runtime safety.

## Stage status

| Stage | Implemented | Validated here | Pending native gates |
|---|---|---|---|
| A: toolchain and fixtures | Flutter 3.41.5 / Dart 3.11.3 pin, matching SDK floor, canonical disposable test roots; intentional Windows path cases retained | SDK identity, formatting, affected tests, locked dependencies unchanged | Clean pinned setup on each new host |
| B: iOS document contracts | Typed document errors, library-change/resume hints, platform-neutral non-Android expiration wording | Dart channel/error/lifecycle contracts | Swift compile, first folder admission, Files changes, extension/lifecycle/device behavior |
| C: desktop storage primitives | Separate macOS/Linux no-replace rename, descriptor-owned locks, metadata durability, filesystem/root capability admission and case sensitivity | Portable primitive/failure contracts and Windows recovery/ownership regressions | Actual Darwin/Linux ABI, filesystem semantics, locks, interruption, full storage, removal and recovery |
| D: bootstrap and migration | macOS/Linux owned backend, bounded legacy settings capture, strict compatible journal decoding, explicit folder reselection with admission before acknowledgement | Settings/root isolation, journal compatibility, selection cancellation, denied access, missing entitlement, failed acknowledgement and unchanged previous selection | Real legacy/completed/interrupted-library corpus, Unicode/case variants and moved folders on native hosts |
| E: permissions and host actions | Native macOS Open/Save panels, app-scoped bookmarks and job-owned access; coordinated owned export candidates; private caches/open/reveal; Linux descriptor portal actions; Command shortcuts on Mac | Mocked grant lifetime, picker/export/cache/watcher contracts; Windows desktop UI/runtime smoke | Signed Mac Debug/Release permissions and safe save; Linux GTK compilation, portal versions, X11/Wayland and sandbox behavior |
| F: Office and packaging | Pinned Office 0.1.15 native recipes, Apple process/Linux library resolution, Pod/Xcode/CMake wiring and licenses/provenance gates | Script syntax, six packaging configuration cases, XML/wiring, existing Windows Office tests, protected Windows/Android builds and package inspection | Build actual Mac/Linux/iOS Office artifacts; link/render Office, PDF and media on each host; signing/distribution acceptance |
| G: settings and resources (partial) | Bounded private mobile settings with native atomic acknowledgement, legacy preservation and truthful failure handling | Private settings migration/persistence/failure tests; Kotlin compiled; LG startup/settings/restart observation | iOS native settings; sustained device workloads and failure injection. Mac telemetry remains the existing conservative unknown-capacity fallback |

## Permission behavior

macOS access is requested through native panels on explicit file/folder actions. Startup can restore an existing library bookmark; it does not repeatedly prompt or silently choose a fallback library. Denial, cancellation and missing entitlement have separate actionable states. The library or job owns its grant through work and cancellation cleanup. Native save uses a system-issued replacement candidate and coordinated publication; it does not assume a selected file grants its parent folder.

Signed Mac checks remain essential: first selection/cancellation, read-only input versus writable library, bookmark restart/staleness, moved or revoked access, volume removal, background scope lifetime, save conflicts and interrupted replacement. No blanket Full Disk Access requirement was added. Shared Windows/Android editor design and existing encryption/package formats were retained.

## Checks completed

Evidence is in `.validation/multiplatform-stage-a`, `.validation/multiplatform-stage-f` and `.validation/multiplatform-stage-builds` (local, private validation artifacts).

- Broad affected suite: 60 files, **610 passed, two native POSIX tests skipped on Windows, two stale UID-comparison assertions failed**. Those assertions were corrected to match the accepted UID-first/no-payload-comparison contract. The affected three-case import/mention suite then passed. This is a broad run plus a successful focused correction, not a claimed single green whole-repository run.
- Final bootstrap/permission/settings suite: **61 passed**, including six new startup/admission cases. Earlier integration suites passed their actual affected cases; two initially requested nonexistent test paths were replaced with the existing suites.
- Changed Dart files formatted. Scoped analysis has **no remaining errors or warnings**; informational style lints remain (21 in the final startup scope). `git diff --check` passed.
- Native Office packaging gates accepted complete metadata and rejected missing engine, wrong pin, wrong ABI, missing license and unsupported CPU. These used fixtures, not new Apple/Linux binaries. PowerShell/Bash syntax and macOS entitlement/Xcode wiring checks passed.
- Protected Windows candidate built in 44.4 seconds with private symbols; ASLR, high-entropy ASLR, DEP, CFG and stack cookie checks passed. Its isolated disposable library/editor rendered normally, held the same process for 20 seconds and closed normally. Working set was approximately 159 MB; CPU time was 0.81 seconds over that observation. No user notes were opened or changed.
- Protected Android Preview built in 67.5 seconds with Dart obfuscation, R8/resource shrinking and separate symbols. API 24 minimum, non-debuggable identity, matching signer, APK ZIP alignment and 64-bit native load alignment checks passed. Eighteen libraries across three ABIs were inspected; this is not minimum/current-API emulator execution.
- Final APK installed as an update on the LG Android 12 phone without uninstalling or clearing app data. Cold launch was approximately 1.46 seconds. Preview/settings controls were observed; no startup, framework, cipher or job-host failures were recorded in the observation. Process identity remained stable. After warmup, a further 20 seconds showed PSS 92,271 → 91,672 KiB. This short observation does not establish sustained large-file performance or absence of leaks.

## Artifacts and preservation

Final local protected Preview: `.validation/multiplatform-stage-builds/preview-candidate-final.apk`.

SHA-256: `2a9dc2276a36637f96aecee0de62c06fc61ad338a786d4ca85686984fdcfb90b`.

The Windows candidate uses compiled disposable validation roots and is not a published normal portable replacement. Accepted Windows/APK copies remain retained. `D:\tools`, `G:\My Drive\App\FutureNotes`, existing tags, actual notes and unrelated files were not modified. The pending shared-attachment/protection fix and its test remain. Preservation evidence is in `implementation-preservation.json`; branch and HEAD remain unchanged. No commit, push, tag or publication occurred. The final normal Preview remains running on the LG; the isolated Windows candidate was closed normally.

## Remaining work and limits

1. macOS: compile Swift, CocoaPods and Office XCFramework on a compatible Mac, then pass signed permission, storage failure/recovery, preview and real workload gates above. Source readiness is provisional until those pass.
2. Linux: compile native runner/Office on a supported GNU/glibc desktop, exercise portal and fallback restrictions on X11/Wayland, and validate filesystem/durability, media dependencies and packaging.
3. iOS: Mac/Xcode/Pods/framework build, extension signing, iPhone/iPad folder access, sharing, lifecycle/background expiration, settings, previews and recovery. No iOS runtime acceptance is claimed.
4. Android: minimum/current API and tablet coverage, notification/failure matrix and sustained large-attachment/thermal measurements were not repeated in this stage. LG validation here is a bounded update/startup/settings check alongside shared automated regression coverage.
5. **G13 remains unchanged:** completed-baseline recovery can still inspect retained payloads. The original plan requires a separate bounded trust/identity design; removing recovery verification without it could compromise predecessor recovery. No new normal-job payload verification passes were added. Every optional verification default remains off, and explicitly saved choices remain respected.

These native gates block a full multiplatform parity claim. No test failure is being treated as native acceptance, and accepted published builds have not been replaced.
