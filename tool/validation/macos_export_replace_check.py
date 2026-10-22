"""Exercise the actual Mac publication code with disposable native files.

This compiles the production types and publication methods verbatim. It checks
replacement, retained predecessors and conflict handling, without a Flutter
mock. It is not a sandbox/picker test; signed-app acceptance is still required.
"""

from pathlib import Path
import subprocess
import sys
import tempfile


FIXTURES = r'''
  private func require(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else {
      fputs("FAIL: \(label)\n", stderr)
      exit(1)
    }
  }

  func run(_ root: URL) throws {
    let manager = FileManager.default
    let original = Data([17, 23, 42, 69, 99])
    let replacement = Data([3, 7, 11])
    for name in ["existing", "new", "changed-destination", "changed-candidate"] {
      print("starting_case=\(name)")
      let directory = root.appendingPathComponent(name, isDirectory: true)
      let staging = directory.appendingPathComponent("staging", isDirectory: true)
      try manager.createDirectory(at: staging, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let destination = directory.appendingPathComponent("synthetic.fnote")
      if name != "new" { try original.write(to: destination, options: .withoutOverwriting) }
      let save = SaveState(directory: staging, expected: try fileStamp(destination))
      save.attempted = true
      try replacement.write(to: save.candidate, options: .withoutOverwriting)
      let candidate = try fileStamp(save.candidate)!
      // Match chooseSaveTarget's Foundation-normalized exact destination grant;
      // Darwin realpath and Foundation can spell /private/var differently.
      let grantedParent = destination.deletingLastPathComponent().standardizedFileURL
        .resolvingSymlinksInPath()
      let grantedPath = grantedParent.appendingPathComponent(destination.lastPathComponent).path
      let grant = Grant(url: destination, bookmark: Data(), identity: "synthetic",
        path: grantedPath, library: false)
      grant.save = save
      let changed = Data([5, 10, 15, 20, 25, 30, 35])
      if name == "changed-destination" { try changed.write(to: destination) }
      if name == "changed-candidate" { try changed.write(to: save.candidate) }
      if name.hasPrefix("changed-") {
        do {
          try publish(grant, save: save, length: candidate.size,
            modified: candidate.modifiedMicros, changed: candidate.changedMicros)
          require(false, "conflicting export must fail")
        } catch let failure as AccessFailure {
          require(failure.code == "conflict", "conflict classification")
        }
        let expectedDestination = name == "changed-destination" ? changed : original
        let actualDestination = try Data(contentsOf: destination)
        require(actualDestination == expectedDestination,
          "conflict preserves current destination")
        require(manager.fileExists(atPath: save.candidate.path), "conflict retains candidate")
        require(manager.fileExists(atPath: staging.path), "conflict retains staging")
      } else {
        do {
          try publish(grant, save: save, length: candidate.size,
            modified: candidate.modifiedMicros, changed: candidate.changedMicros)
        } catch let failure as AccessFailure {
          let destinationNow = try fileStamp(destination)
          let candidateNow = try fileStamp(save.candidate)
          print("failure_code=\(failure.code)")
          print("destination_revision_matches=\(destinationNow == save.expected)")
          print("candidate_revision_matches=\(candidateNow == candidate)")
          throw failure
        }
        let published = try Data(contentsOf: destination)
        require(published == replacement, "published replacement bytes")
        require(!manager.fileExists(atPath: save.candidate.path), "candidate consumed")
        let siblings = try manager.contentsOfDirectory(atPath: directory.path).sorted()
        if name == "existing" {
          let retained = try manager.contentsOfDirectory(at: staging,
            includingPropertiesForKeys: nil)
          require(retained.count == 1, "one retained predecessor")
          require(retained[0].pathExtension == "previous", "predecessor file kind")
          let predecessor = try Data(contentsOf: retained[0])
          require(predecessor == original, "complete predecessor bytes")
          require(siblings == ["staging", "synthetic.fnote"], "no destination sibling backup")
        } else {
          require(!manager.fileExists(atPath: staging.path), "empty new-file staging removed")
          require(siblings == ["synthetic.fnote"], "new-file destination only")
        }
      }
      print("PASS: \(name)")
    }
  }
'''


def section(source, start, end):
    first = source.index(start)
    return source[first:source.index(end, first)]


def main():
    if sys.platform != "darwin":
        raise SystemExit("This native publication check requires macOS.")
    repo = Path(__file__).resolve().parents[2]
    source = (repo / "macos/Runner/NativeFileAccess.swift").read_text()
    types = section(source, "  private struct AccessFailure:", "  private static let bookmarkKey")
    methods = section(source, "  private func fileStamp(", "  private func requireEntitlements(")
    program = (
        "import Foundation\nimport Darwin\nfinal class NativePublicationProbe {\n"
        + types + methods + FIXTURES + "\n}\n"
        + 'do { try NativePublicationProbe().run(URL(fileURLWithPath: CommandLine.arguments[1], '
          'isDirectory: true)) } catch {\n'
        + 'let native = error as NSError\n'
        + 'let domain = native.domain == NSCocoaErrorDomain ? 1 : '
          '(native.domain == NSPOSIXErrorDomain ? 2 : 0)\n'
        + 'fputs("FAIL: native domain=\\(domain) code=\\(native.code)\\n", stderr)\nexit(1)\n}\n'
    )
    with tempfile.TemporaryDirectory(prefix="fn-macos-export-replace-") as owned:
        root = Path(owned).resolve()
        fixture = root / "fixtures"
        fixture.mkdir()
        swift = root / "main.swift"
        swift.write_text(program)
        executable = root / "replace-check"
        subprocess.run(["/usr/bin/xcrun", "swiftc", str(swift), "-o", str(executable)],
                       check=True)
        subprocess.run([str(executable), str(fixture)], check=True)
    print("PASS: native publication fixtures; sandbox/picker acceptance still required")


if __name__ == "__main__":
    main()
