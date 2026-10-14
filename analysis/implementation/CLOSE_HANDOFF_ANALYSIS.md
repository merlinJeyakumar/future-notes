# Shutdown observer lifetime race

Status: static code evidence; no patch, regression execution or new runtime test.
The user selected analysis only after the failed manual close validation.

## Observed runtime

The original close log records storage completion at 40 ms followed by the
dashboard returning exit. A later poll of the same launch session, 94245,
returned terminal exit code 0. Additional output records another Flutter-handled
WM_CLOSE and dashboard exit response, followed by WM_CLOSE and WM_DESTROY.
No agent input, restart or termination occurred. The log does not establish
whether the additional request was a user click or its exact elapsed delay.
One-click completion failed according to the user's report.

## Specific source mechanism

The installed SDK and current application have the following sequence:

1. WidgetsBinding.handleRequestAppExit in
   C:/src/flutter/packages/flutter/lib/src/widgets/binding.dart:843 copies the
   observer list and awaits each observer sequentially.
2. The dashboard registers its AppLifecycleListener in initState before its
   child text fields are mounted. Its exit handler sets _shutdownStarted and
   awaits asynchronous storage cleanup.
3. DashboardScreen.build at
   lib/features/dashboard/views/dashboard_screen.dart:771 returns a replacement
   Scaffold when _shutdownStarted is true. The mounted editor/sidebar subtree
   is removed while the exit request is in flight.
4. EditableTextState creates an AppLifecycleListener at
   C:/src/flutter/packages/flutter/lib/src/widgets/editable_text.dart:3231 and
   disposes it at :3464. Removing this listener from the binding does not remove
   it from the already-captured list.
5. AppLifecycleListener.didRequestAppExit at
   C:/src/flutter/packages/flutter/lib/src/widgets/app_lifecycle_listener.dart:204
   checks that it is not disposed. Debug mode throws on a disposed listener.
6. Observer aggregation does not catch that failure. The platform-channel
   handler therefore cannot return its successful aggregate exit response.
   The installed Windows PlatformHandler only calls QuitApplication after a
   successful response containing response=exit; its error callback is null.

This is a concrete use-after-disposal path in the shutdown UI design. It
explains how successful cleanup and a successful dashboard callback can coexist
with a window left open. On a later request the removed listeners are absent
from the new snapshot, so aggregation can succeed. The actual exception was not
captured in the runtime output, so matching this mechanism to the observed
failure remains to be demonstrated by an authorized regression/manual check.
Do not call the exact runtime root cause proven or attribute it to sandboxing.

## Small compatible repair proposal

Keep the original dashboard/editor subtree mounted throughout the exit request.
Present shutdown status with an overlay on a stable Stack; block input and
shortcuts while cleanup runs, without changing the subtree's ancestor structure
at shutdown. Controllers and lifecycle listeners should dispose only when the
application actually unmounts. Retain dirty-draft resolution, one shared cleanup
attempt, original cancellable exit response and truthful cleanup failures.

Do not force process exit, bypass other observers, patch the SDK or change
storage/encryption. A diagnostic binding alone would identify the failure but
would not repair this lifetime violation.

An appropriate regression must invoke the real binding exit aggregation with
mounted text fields, hold cleanup pending, pump the shutdown UI, then complete
cleanup and assert a successful aggregate response without disposed-listener
exceptions. Also cover cancelled drafts and failed cleanup. Tests of only the
ShutdownSequence helper do not cover this join. One lint-first affected gate
and a user-performed isolated one-click close would be required before claiming
the repair validated. None is authorized by the current analysis-only decision.
