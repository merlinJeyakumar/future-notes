import Cocoa
import Darwin
import FlutterMacOS
import Security

/// One process owns all scopes. Closing a picker/window does not release a job's
/// reference; only the final lease release balances the successful scope start.
final class NativeFileAccess {
  private struct AccessFailure: Error {
    let code: String
    let message: String
  }

  private final class Grant {
    let url: URL
    let bookmark: Data
    let identity: String
    let path: String
    let library: Bool
    var leases = Set<String>()
    var save: SaveState?

    init(url: URL, bookmark: Data, identity: String, path: String, library: Bool) {
      self.url = url
      self.bookmark = bookmark
      self.identity = identity
      self.path = path
      self.library = library
    }

    deinit {
      if let save = save, !save.attempted { _ = Darwin.rmdir(save.directory.path) }
      url.stopAccessingSecurityScopedResource()
    }
  }

  private struct Stamp: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    init(_ info: stat) {
      device = info.st_dev; inode = info.st_ino; size = info.st_size
      modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
      changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
    }
    var modifiedMicros: Int64 { Int64(modifiedSeconds) * 1_000_000 + Int64(modifiedNanos / 1000) }
    var changedMicros: Int64 { Int64(changedSeconds) * 1_000_000 + Int64(changedNanos / 1000) }
  }

  private final class SaveState {
    let directory: URL
    var candidate: URL
    let expected: Stamp?
    var attempted = false
    init(directory: URL, expected: Stamp?) {
      self.directory = directory; self.expected = expected
      candidate = directory.appendingPathComponent(".future-notes-export-\(UUID().uuidString).staged")
    }
  }

  private static let bookmarkKey = "futureNotes.selectedLibraryBookmark.v1"
  private static let bookmarksKey = "futureNotes.libraryBookmarks.v1"
  private let defaults: UserDefaults
  private var grants: [String: Grant] = [:]
  private var leases: [String: String] = [:]
  private var channel: FlutterMethodChannel?
  private let exportQueue = DispatchQueue(label: "future-notes.macos-export")

  private func cacheRoot() throws -> URL {
    let base = try FileManager.default.url(for: .cachesDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
    let root = base.appendingPathComponent("FutureNotes/AttachmentCache", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    return root.standardizedFileURL.resolvingSymlinksInPath()
  }

  init(messenger: FlutterBinaryMessenger, defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let channel = FlutterMethodChannel(
      name: "future_notes/macos_file_access", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        try self.handle(call, result: result)
      } catch let failure as AccessFailure {
        result(FlutterError(code: failure.code, message: failure.message, details: nil))
      } catch {
        let nsError = error as NSError
        let denied = nsError.domain == NSCocoaErrorDomain &&
          [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(nsError.code)
        result(FlutterError(code: denied ? "access_denied" : "access_unavailable",
          message: denied ? "Access to the selected location was denied." :
            "The selected location is unavailable. Choose it again to restore access.",
          details: nil))
      }
    }
  }

  deinit { channel?.setMethodCallHandler(nil) }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "chooseLibrary", "chooseExportDirectory":
      try requireEntitlements()
      let panel = NSOpenPanel()
      panel.title = call.method == "chooseLibrary" ? "Choose notes folder" : "Save selected attachments"
      panel.prompt = "Choose folder"
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let url = panel.url else { result(nil); return }
      // Powerbox starts access for panel URLs. Transfer to our independently
      // resolved bookmark scope, then relinquish the panel's temporary access.
      defer { url.stopAccessingSecurityScopedResource() }
      result(try createGrant(url: url, library: true))
    case "restoreLibrary":
      try requireEntitlements()
      let expected = args["expectedPath"] as? String
      let records = defaults.dictionary(forKey: Self.bookmarksKey) ?? [:]
      guard let record = (expected.flatMap { records[$0] as? [String: Any] }) ??
        defaults.dictionary(forKey: Self.bookmarkKey) else {
        result(nil); return
      }
      guard let data = record["bookmark"] as? Data,
        let identity = record["identity"] as? String,
        let acceptedPath = record["path"] as? String else {
        throw AccessFailure(code: "invalid_bookmark", message: "Choose the notes folder again.")
      }
      let value = try createGrant(bookmark: data, library: true)
      let restoredPath = value["path"] as! String
      if value["identity"] as? String != identity || restoredPath != acceptedPath ||
        (args["expectedPath"] as? String).map({
          URL(fileURLWithPath: $0).standardizedFileURL.path != restoredPath
        }) == true {
        release(value["leaseToken"] as! String)
        throw AccessFailure(code: "library_changed",
          message: "The notes folder has moved or changed. Choose it again to restore access.")
      }
      // Stale data is refreshed by acceptLibrary only after storage admission.
      result(value)
    case "acceptLibrary":
      let grant = try getGrant(args)
      guard grant.library else {
        throw AccessFailure(code: "wrong_grant", message: "This grant is not a notes folder.")
      }
      var records = defaults.dictionary(forKey: Self.bookmarksKey) ?? [:]
      guard records[grant.path] != nil || records.count < 128 else {
        throw AccessFailure(code: "grant_limit", message: "Too many retained folder grants.")
      }
      records[grant.path] = ["bookmark": grant.bookmark, "identity": grant.identity,
        "path": grant.path]
      defaults.set(records, forKey: Self.bookmarksKey)
      result(nil)
    case "acquire":
      let grant = try getGrant(args)
      let token = args["grantToken"] as! String
      result(acquire(grant, token: token))
    case "release":
      guard let lease = args["leaseToken"] as? String else {
        throw AccessFailure(code: "invalid_grant", message: "Invalid file access lease.")
      }
      release(lease)
      result(nil)
    case "chooseInputs":
      try requireEntitlements()
      let panel = NSOpenPanel()
      panel.title = "Choose files"
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.allowsMultipleSelection = args["allowMultiple"] as? Bool ?? true
      if let extensions = args["extensions"] as? [String], !extensions.isEmpty {
        panel.allowedFileTypes = extensions
      }
      guard panel.runModal() == .OK else { result(nil); return }
      let selected = panel.urls
      defer { for url in selected { url.stopAccessingSecurityScopedResource() } }
      var values = [[String: Any]]()
      do {
        for url in selected { values.append(try createGrant(url: url, library: false)) }
      } catch {
        for value in values { release(value["leaseToken"] as! String) }
        throw error
      }
      result(values)
    case "chooseSaveTarget":
      try requireEntitlements()
      let panel = NSSavePanel()
      panel.title = "Save export"
      panel.canCreateDirectories = true
      if let name = args["suggestedName"] as? String,
        !name.isEmpty, !name.contains("/"), !name.contains("\0") {
        panel.nameFieldStringValue = name
      }
      guard panel.runModal() == .OK, let url = panel.url else { result(nil); return }
      defer { url.stopAccessingSecurityScopedResource() }
      guard url.startAccessingSecurityScopedResource() else {
        throw AccessFailure(code: "access_denied", message: "Access to the save destination was denied.")
      }
      var owned = false
      defer { if !owned { url.stopAccessingSecurityScopedResource() } }
      // NSSavePanel grants this destination, not arbitrary sibling paths. The
      // publication adapter must retain this lease for its complete handoff.
      let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
      var info = stat()
      guard Darwin.stat(parent.path, &info) == 0 else {
        throw AccessFailure(code: "access_unavailable", message: "The save destination is unavailable.")
      }
      let path = parent.appendingPathComponent(url.lastPathComponent).path
      let identity = "destination:\(info.st_dev):\(info.st_ino):\(url.lastPathComponent)"
      let grant = Grant(url: url, bookmark: Data(), identity: identity, path: path, library: false)
      let expected = try fileStamp(URL(fileURLWithPath: path))
      // The OS, rather than a guessed sibling pathname, issues staging access
      // on the destination volume for a coordinated safe save.
      let replacement = try FileManager.default.url(for: .itemReplacementDirectory,
        in: .userDomainMask, appropriateFor: url, create: true)
        .standardizedFileURL.resolvingSymlinksInPath()
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
      grant.save = SaveState(directory: replacement, expected: expected)
      let token = UUID().uuidString
      grants[token] = grant
      owned = true
      result(["grantToken": token, "leaseToken": acquire(grant, token: token),
        "path": path, "identity": identity, "candidate": grant.save!.candidate.path])
    case "nextSaveCandidate":
      let grant = try getGrant(args)
      guard let save = grant.save, !save.attempted else {
        throw AccessFailure(code: "invalid_grant", message: "The save lease is unavailable.")
      }
      save.candidate = save.directory.appendingPathComponent(".future-notes-export-\(UUID().uuidString).staged")
      result(save.candidate.path)
    case "publishSave":
      let grant = try getGrant(args)
      guard let save = grant.save, !save.attempted,
        let length = args["length"] as? NSNumber,
        let modified = args["modifiedMicros"] as? NSNumber,
        let changed = args["changedMicros"] as? NSNumber else {
        throw AccessFailure(code: "invalid_grant", message: "The save lease is unavailable.")
      }
      save.attempted = true
      exportQueue.async {
        do {
          try self.publish(grant, save: save, length: length.int64Value,
            modified: modified.int64Value, changed: changed.int64Value)
          DispatchQueue.main.async { result(nil) }
        } catch let failure as AccessFailure {
          DispatchQueue.main.async { result(FlutterError(code: failure.code,
            message: failure.message, details: nil)) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "recovery_required",
            message: "The export could not be acknowledged. Retained files require recovery.", details: nil)) }
        }
      }
    case "retainDroppedInputs":
      guard let paths = args["paths"] as? [String], !paths.isEmpty, paths.count <= 128 else {
        throw AccessFailure(code: "invalid_path", message: "Choose regular files to attach.")
      }
      var values = [[String: Any]]()
      do {
        for path in paths {
          guard path.hasPrefix("/"), !path.contains("\0"),
            !path.split(separator: "/").contains("..") else {
            throw AccessFailure(code: "invalid_path", message: "Choose regular files to attach.")
          }
          // Powerbox/drop grants must already exist. A path cannot create
          // sandbox permission: bookmark creation fails if authority is absent.
          values.append(try createGrant(url: URL(fileURLWithPath: path), library: false))
        }
      } catch {
        for value in values { release(value["leaseToken"] as! String) }
        throw error
      }
      result(values)
    case "revealLibraryFile":
      guard let path = args["path"] as? String, path.hasPrefix("/"),
        !path.contains("\0"), !path.split(separator: "/").contains("..") else {
        throw AccessFailure(code: "invalid_path", message: "Invalid note location.")
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      let documents = try FileManager.default.url(for: .documentDirectory,
        in: .userDomainMask, appropriateFor: nil, create: false)
        .appendingPathComponent("UserData", isDirectory: true).resolvingSymlinksInPath().path
      let roots = grants.values.filter { $0.library }.map { $0.path } + [documents]
      var info = stat()
      guard roots.contains(where: { url.path.hasPrefix($0 + "/") }),
        Darwin.lstat(path, &info) == 0,
        [mode_t(S_IFREG), mode_t(S_IFDIR)].contains(info.st_mode & mode_t(S_IFMT)) else {
        throw AccessFailure(code: "invalid_path", message: "The note location is unavailable.")
      }
      NSWorkspace.shared.activateFileViewerSelecting([url])
      result(nil)
    case "cacheRoot":
      result(try cacheRoot().path)
    case "openFile", "revealFile":
      guard let path = args["path"] as? String, path.hasPrefix("/") else {
        throw AccessFailure(code: "invalid_path", message: "Invalid attachment path.")
      }
      let root = try cacheRoot()
      let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      var info = stat()
      guard url.path.hasPrefix(root.path + "/"), Darwin.lstat(path, &info) == 0,
        info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
        throw AccessFailure(code: "invalid_path", message: "Only private attachment files can be opened.")
      }
      if call.method == "revealFile" {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } else if !NSWorkspace.shared.open(url) {
        throw AccessFailure(code: "open_failed", message: "No application could open this attachment.")
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func fileStamp(_ url: URL) throws -> Stamp? {
    var info = stat()
    if Darwin.lstat(url.path, &info) != 0 {
      if errno == ENOENT { return nil }
      throw AccessFailure(code: "access_unavailable", message: "The export location is unavailable.")
    }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw AccessFailure(code: "invalid_path", message: "Choose a regular export file.")
    }
    return Stamp(info)
  }

  private func publish(_ grant: Grant, save: SaveState, length: Int64,
    modified: Int64, changed: Int64) throws {
    guard length >= 0, let candidate = try fileStamp(save.candidate),
      candidate.size == length, candidate.modifiedMicros == modified,
      candidate.changedMicros == changed else {
      throw AccessFailure(code: "conflict", message: "The prepared export changed; the destination was retained.")
    }
    var coordinationError: NSError?
    var operationError: Error?
    var finished = false
    NSFileCoordinator().coordinate(writingItemAt: grant.url, options: .forReplacing,
      error: &coordinationError) { destination in
      do {
        let resolved = destination.deletingLastPathComponent().standardizedFileURL
          .resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent)
        guard resolved.path == grant.path,
          try self.fileStamp(destination) == save.expected,
          try self.fileStamp(save.candidate) == candidate else {
          throw AccessFailure(code: "conflict", message: "The export destination changed; retained files were not overwritten.")
        }
        if save.expected != nil {
          let backup = ".future-notes-export-\(UUID().uuidString).previous"
          _ = try FileManager.default.replaceItemAt(destination, withItemAt: save.candidate,
            backupItemName: backup, options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
        } else {
          let code = save.candidate.path.withCString { from in
            destination.path.withCString { to in Darwin.renamex_np(from, to, 4) }
          }
          guard code == 0 else {
            throw AccessFailure(code: "recovery_required",
              message: "The export could not be saved; the prepared file was retained.")
          }
        }
        guard let published = try self.fileStamp(destination), published.size == length else {
          throw AccessFailure(code: "recovery_required", message: "The saved export could not be acknowledged.")
        }
        // Foundation performs the coordinated safe replacement. An exact
        // NSSavePanel grant does not authorize opening its parent directory;
        // do not invent that authority for an additional directory operation.
        // The owned candidate was already flushed and closed by its writer.
        finished = true
      } catch { operationError = error }
    }
    if let error = coordinationError { throw error }
    if let error = operationError { throw error }
    guard finished else {
      throw AccessFailure(code: "recovery_required", message: "The export could not be acknowledged.")
    }
    // Only an empty OS-issued replacement folder is removed. Unexpected or
    // ambiguous material is retained, never recursively deleted.
    _ = Darwin.rmdir(save.directory.path)
  }

  private func requireEntitlements() throws {
    guard let task = SecTaskCreateFromSelf(nil) else {
      throw AccessFailure(code: "entitlement_unavailable",
        message: "The app's signed file permissions could not be read.")
    }
    for key in ["com.apple.security.app-sandbox",
      "com.apple.security.files.user-selected.read-write",
      "com.apple.security.files.bookmarks.app-scope"] {
      guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? Bool,
        value else {
        throw AccessFailure(code: "entitlement_missing",
          message: "This build is missing its signed selected-file permissions.")
      }
    }
  }

  private func createGrant(url: URL, library: Bool) throws -> [String: Any] {
    let options: URL.BookmarkCreationOptions = library ? [.withSecurityScope] :
      [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    let data = try url.bookmarkData(options: options,
      includingResourceValuesForKeys: nil, relativeTo: nil)
    return try createGrant(bookmark: data, library: library)
  }

  private func createGrant(bookmark: Data, library: Bool) throws -> [String: Any] {
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark,
      options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard url.startAccessingSecurityScopedResource() else {
      throw AccessFailure(code: "access_denied",
        message: "Access to the selected location was denied. Choose it again to restore access.")
    }
    var owned = false
    defer { if !owned { url.stopAccessingSecurityScopedResource() } }
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    if library {
      let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .isUbiquitousItemKey])
      guard values.volumeIsLocal == true, values.isUbiquitousItem != true else {
        throw AccessFailure(code: "unsupported_location",
          message: "Choose a local or removable-device notes folder.")
      }
    }
    var info = stat()
    guard Darwin.stat(path, &info) == 0 else {
      throw AccessFailure(code: "access_unavailable", message: "The selected location is unavailable.")
    }
    let isDirectory = info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    let isFile = info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    guard library ? isDirectory : isFile else {
      throw AccessFailure(code: "unsupported_location", message: "Choose a supported local file or folder.")
    }
    guard FileManager.default.isReadableFile(atPath: path),
      !library || FileManager.default.isWritableFile(atPath: path) else {
      throw AccessFailure(code: "access_denied", message: library ?
        "The notes folder must allow reading and writing." : "The selected file cannot be read.")
    }
    let options: URL.BookmarkCreationOptions = library ? [.withSecurityScope] :
      [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    var refreshed = bookmark
    if stale {
      refreshed = try url.bookmarkData(options: options,
        includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    let identity = "\(info.st_dev):\(info.st_ino)"
    let grant = Grant(url: url, bookmark: refreshed, identity: identity, path: path, library: library)
    let token = UUID().uuidString
    grants[token] = grant
    owned = true
    var value: [String: Any] = ["grantToken": token,
      "leaseToken": acquire(grant, token: token), "path": path, "identity": identity]
    if !library { value["name"] = url.lastPathComponent; value["length"] = info.st_size }
    return value
  }

  private func getGrant(_ args: [String: Any]) throws -> Grant {
    guard let token = args["grantToken"] as? String, let grant = grants[token] else {
      throw AccessFailure(code: "invalid_grant", message: "File access has ended. Choose the location again.")
    }
    if !grant.bookmark.isEmpty {
      var info = stat()
      guard Darwin.stat(grant.path, &info) == 0,
        "\(info.st_dev):\(info.st_ino)" == grant.identity else {
        throw AccessFailure(code: "library_changed",
          message: "The selected location has changed. Choose it again to restore access.")
      }
    }
    return grant
  }

  private func acquire(_ grant: Grant, token: String) -> String {
    let lease = UUID().uuidString
    grant.leases.insert(lease)
    leases[lease] = token
    return lease
  }

  private func release(_ lease: String) {
    guard let token = leases.removeValue(forKey: lease), let grant = grants[token] else { return }
    grant.leases.remove(lease)
    if grant.leases.isEmpty { grants.removeValue(forKey: token) }
  }
}
