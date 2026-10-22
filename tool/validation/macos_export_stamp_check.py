"""Compare the actual native Stamp implementation to a real Dart FileStat receipt.

macOS only. Uses one owned, one-byte temporary file and never opens a library.
The native probe is compiled from the production Stamp, not a rewritten formula.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


DART_PROBE = r"""
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> args) async {
  final stat = await File(args.single).stat();
  print(jsonEncode({
    'length': stat.size,
    'modified': stat.modified.microsecondsSinceEpoch,
    'changed': stat.changed.microsecondsSinceEpoch,
  }));
}
"""

SWIFT_PROBE = r"""
func require(_ condition: @autoclosure () -> Bool, _ label: String) {
  guard condition() else {
    fputs("FAIL: \(label)\n", stderr)
    exit(1)
  }
}
var info = stat()
require(Darwin.lstat(CommandLine.arguments[1], &info) == 0, "fixture stat")
let original = Stamp(info)
let length = Int64(CommandLine.arguments[2])!
let modified = Int64(CommandLine.arguments[3])!
let changed = Int64(CommandLine.arguments[4])!
require(original.size == length, "receipt size")
require(original.modifiedMicros == modified, "Dart/native modified precision")
require(original.changedMicros == changed, "Dart/native changed precision")
require(info.st_mtimespec.tv_nsec % 1_000_000 != 0, "submillisecond fixture")

// Changes invisible to Dart's millisecond receipt remain visible to the exact
// native Stamp used by the subsequent coordinated-publication comparison.
var mutation = info
mutation.st_mtimespec.tv_nsec -= 1
require(Stamp(mutation).modifiedMicros == original.modifiedMicros,
  "same millisecond mtime")
require(Stamp(mutation) != original, "native nanosecond mtime conflict")
mutation = info
if mutation.st_ctimespec.tv_nsec % 1_000_000 == 0 {
  mutation.st_ctimespec.tv_nsec += 1
} else {
  mutation.st_ctimespec.tv_nsec -= 1
}
require(Stamp(mutation).changedMicros == original.changedMicros,
  "same millisecond ctime")
require(Stamp(mutation) != original, "native nanosecond ctime conflict")
mutation = info
mutation.st_ino += 1
require(Stamp(mutation) != original, "native inode conflict")
mutation = info
mutation.st_size += 1
require(Stamp(mutation) != original, "native length conflict")

// A second-boundary edge case must floor nanoseconds before adding seconds;
// rounding the total signed microseconds towards zero would be incorrect.
var beforeEpoch = stat()
beforeEpoch.st_mtimespec = timespec(tv_sec: -1, tv_nsec: 999_999_999)
beforeEpoch.st_ctimespec = timespec(tv_sec: -1, tv_nsec: 999_999_999)
require(Stamp(beforeEpoch).modifiedMicros == -1000, "negative mtime")
require(Stamp(beforeEpoch).changedMicros == -1000, "negative ctime")
print("PASS: Dart receipt precision and full native identity checks")
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", required=True, help="Pinned Dart executable")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This native regression check requires macOS.")
    repo = Path(__file__).resolve().parents[2]
    source = (repo / "macos/Runner/NativeFileAccess.swift").read_text()
    start = source.index("  private struct Stamp: Equatable {")
    end = source.index("\n  private final class SaveState", start)
    # Only lift the enclosing type's access level for this standalone probe;
    # its fields, equality synthesis and timestamp implementations are verbatim.
    stamp = source[start:end].replace("private struct Stamp:", "struct Stamp:", 1)
    # The native publication check must continue comparing the complete stamp.
    assert "try self.fileStamp(save.candidate) == candidate" in source
    with tempfile.TemporaryDirectory(prefix="fn-macos-export-stamp-") as owned:
        root = Path(owned)
        fixture = root / "synthetic.bin"
        with fixture.open("xb") as output:
            output.write(b"\x11")
            output.flush()
            os.fsync(output.fileno())
        # Deliberately preserve fractional milliseconds to expose the old bug.
        os.utime(fixture, ns=(1767323045972123456, 1767323045972123456))
        dart = root / "receipt.dart"
        dart.write_text(DART_PROBE)
        receipt = json.loads(subprocess.check_output(
            [args.dart, str(dart), str(fixture)], text=True
        ))
        swift = root / "main.swift"
        swift.write_text("import Foundation\nimport Darwin\n" + stamp + SWIFT_PROBE)
        executable = root / "stamp-check"
        subprocess.run(["/usr/bin/xcrun", "swiftc", str(swift), "-o", str(executable)],
                       check=True)
        subprocess.run([str(executable), str(fixture), str(receipt["length"]),
                        str(receipt["modified"]), str(receipt["changed"])], check=True)


if __name__ == "__main__":
    main()
