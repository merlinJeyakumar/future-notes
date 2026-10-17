# Android orientation, memory pressure and diagnostics

17 October 2026. Android preview only; test suites remain deferred by the user.
iOS build/device validation remains held. No storage/encryption migration.

## Findings and changes

- The existing manifest handles orientation/size configuration changes and
  `FutureNotesApplication` retains one Flutter engine. No replacement writer or
  note reload was added. Engine and Activity lifecycle events now make this
  ownership observable.
- Previously, attachment capacity used system memory and thermal state without
  an app-specific work allowance. Android capacity now subtracts the system's
  low-memory threshold, reserves 16 MiB of managed-heap headroom and caps the
  work allowance at half the Android memory class. This is conservative worker
  admission, not an exact hard limit on the combined Dart/native/GPU heaps.
- Running/background pressure reduces the scheduler capacity factor; critical
  pressure suspends preparation admission/duty through the existing scheduler.
  A 15-second callback cooldown expires into live memory/thermal reassessment.
  Android's UI_HIDDEN event alone does not count as memory pressure. Low-memory
  telemetry can keep the limit active after cooldown. No password, unlocked
  session, decrypted disk cache or library object is evicted by this handling.
- The retained application forwards memory warnings to Flutter even without an
  attached Activity. Flutter's PaintingBinding already clears unused decoded
  images. Active image references, players and editors are not blindly disposed.
- Added typed mobile diagnostic events transported to Android logcat tag
  `FutureNotes`. Events include engine reuse, configuration dimensions,
  lifecycle, memory limits, job phases/elapsed milliseconds, service events,
  recovery failures and framework/async errors. Job correlation numbers are
  ephemeral sequence numbers, not persistent IDs. Only bounded numeric fields
  are accepted alongside fixed event names. No content, filenames, note IDs,
  provider URIs, paths, credentials or raw exception messages are added.
- Logging occurs on phase/count/state changes, not every byte. Dart diagnostic
  transport has at most 16 in-flight messages and failures never affect work.
  Existing framework/async error handlers remain in effect. This is diagnostic
  logging, not a new persistent crash-report upload or an in-app log viewer.

## Automated checks and build

- Changed Dart files formatted. Scoped analysis: zero errors/warnings, eleven
  existing informational notices. Whitespace check passed. Kotlin compiled in
  the protected release build. No dependency versions changed.
- Eleven desktop presentation files and desktop MyApp still match v1.4.1.
  Desktop capacity sampling is unchanged; the new pressure field applies to
  mobile telemetry. The shared VM, scheduler and encryption were not edited
  during this change.
- Previous accepted APK and source backups:
  `.validation/mobile-resilience-before/`. Previous APK SHA-256:
  `e3422bc246890456c325020d1d0478d33070152b11277df755816220ac755e58`.
- Protected preview build passed in 65.6 seconds. APK 131,294,681 bytes,
  SHA-256 `2314c19b9324117829d4fffc26fd6e7105c2b7d4b1b9f985e0859f928d6a3976`.
  Eighteen native libraries present; 64-bit ELF and ZIP 16 KB alignment checks
  passed. Existing 32-bit PDFium alignment limitation remains.
- `adb install -r` succeeded without clear/uninstall. Cold launch Status ok,
  TotalTime 1480 ms, WaitTime 1496 ms on LG LM-G900 / Android 12 / arm64.

## Device observations and limitations

- Final 45.3-second check rotated through 0/1/0/3/0/1/0, retained PID 28852,
  and acknowledged both orientations in native and Dart metrics.
- `am start -W -R 2` actually destroyed the top Activity and launched another:
  one ENGINE_CREATED, two ACTIVITY_CREATED, one ACTIVITY_DESTROYED and one
  ENGINE_REUSED. Dart started once. The initial Home/restore attempt did not
  recreate an Activity, despite writing always_finish_activities. That setting
  was restored, and the first claim of recreation was corrected in chat.
- RUNNING_LOW and RUNNING_CRITICAL callbacks reached native and Flutter code;
  capacity logs showed limits 1 and 2, followed by 0 after cooldown and an actual
  Home/restore UI_HIDDEN callback. This validates callback propagation and
  capacity reporting, not actual allocation-pressure survival with active jobs.
- Two diagnostic commands were rejected by Android: HIDDEN on a foreground
  process, and raw 0 below the prior trim level. They were removed from the
  helper; both attempts preserved the process and restored device settings.
- No fatal/layout-error matches or diagnostic failure events in inspected
  process logs. PSS went from 143,562 to 130,518 KiB; Activities=1, Views=8,
  AppContexts=6 before and after. This short idle observation is not a leak-free
  claim. Final additional 20-second startup observation remained resumed,
  unlocked, same PID, no fatal/layout errors; PSS 144,940 KiB.
- One rapid-rotation screenshot showed a partially black frame. A later settled
  landscape capture filled the window correctly. A follow-up sampled sixteen
  frames at roughly 1/2/3.5/5.5 seconds across portrait and both landscape
  directions; all sampled right-content pixels matched the app background.
  The partial capture was not reproduced; its cause is unconfirmed. Do not claim
  every intermediate frame or active editor/player transition has been validated.
- Evidence: `.validation/mobile-resilience-runtime.json`,
  `.validation/mobile-resilience-final-startup.json`,
  `.validation/mobile-resilience-rotation-frames.json` and related screenshots.
  The two failed shell attempts are retained separately.
- Manual acceptance requested: unsaved text/caret/mode survival and attachment
  completion across rotation, including any black region. Real low-memory kills,
  process-death draft recovery, sustained large jobs, live previews and tablet
  layouts remain unvalidated in this scope. No note was opened or edited by the
  automated device checks. One retained interrupted demo-job notification was
  visible; it was not discarded or automatically resumed.
- All temporary rotation/developer settings restored. No commit, push, tag,
  release, D:\tools or Windows executable changes.

## Reading the added Android logs

Use the local SDK's adb with the connected device, for example:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 192.168.0.30:5555 logcat -d -s 'FutureNotes:I' '*:S'
```

Phase indices follow `AttachmentJobPhase` (queued=0 through failed=9); operation
indices follow `AttachmentJobOperation` (add=0, open=1, protection=2, export=3,
import=4). Lifecycle indices follow Flutter's AppLifecycleState. Capacity limit
0 means normal memory admission, 1 reduced/insufficient work allowance and 2
critical suspension; thermal limits still apply independently.

References: [Android configuration changes](https://developer.android.com/guide/topics/resources/runtime-changes),
[Android memory management](https://developer.android.com/topic/performance/memory/manage-app-memory),
[Flutter memory-pressure handling](https://api.flutter.dev/flutter/painting/PaintingBinding/handleMemoryPressure.html).
