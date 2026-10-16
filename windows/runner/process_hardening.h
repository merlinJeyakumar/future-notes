#ifndef RUNNER_PROCESS_HARDENING_H_
#define RUNNER_PROCESS_HARDENING_H_

#include <windows.h>

struct ProcessHardeningResult {
  const char* failed_stage;
  DWORD error;
  bool ok() const { return failed_stage == nullptr; }
};

// Call before COM, Flutter, plugins or storage. Policies affect this process only.
// They reduce injection avenues; they do not block an administrator/debugger.
ProcessHardeningResult ApplyProcessHardening();

#endif  // RUNNER_PROCESS_HARDENING_H_
