# Injected note-service analyzer summary

Observed on Windows, 2026-10-13, after the approved separator correction:

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
```

Exit 0, 16.5 seconds, 99 diagnostics: 97 informational, two warnings, no errors.
This is a summary of inspected output, not a raw-output archive.

Compared with the preceding settings gate (also 99 diagnostics):

- Removed `unnecessary_underscores` at settings_service.dart:195:38.
- Added `unnecessary_import` at owned_note_service_test.dart:1:8: dart:async is
  already exported by flutter_test. It is informational, not a new warning.
- Existing FileService/view-model diagnostic locations shifted with source edits;
  their rules/messages were retained.
- Original warnings remain: unused dart:io in sidebar.dart:1:8 and unused
  flutter/material.dart in file_details_dialog_test.dart:1:8.

The approved nonfatal baseline exception remains explicit. Diagnostics are not
closed merely because this command returned success.
