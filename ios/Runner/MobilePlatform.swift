import Flutter
import UIKit
import Foundation
import CryptoKit
import Security
import Darwin
import os

/// Native document capabilities for the shared provider coordinator. Bookmarks
/// identify selected roots; child tokens are opaque, process-local capabilities.
/// NSFileCoordinator protects individual accesses, not a multi-file transaction.
final class MobilePlatform: NSObject, UIDocumentPickerDelegate {
  private weak var host: UIViewController?
  private let queue = DispatchQueue(label: "future-notes.documents")
  private var channels: [FlutterMethodChannel] = []
  private var picker: FlutterResult?
  private var pickingFolder = false
  private var pickingMultiple = false
  private var exportingFile = false
  private var roots: [String: URL] = [:]
  private var entries: [String: (String, URL)] = [:]
  private var entryKeys: [String: String] = [:]
  private var leases: [String: (String, URL, FileHandle, Bool)] = [:]
  private var interaction: UIDocumentInteractionController?
  private var background: UIBackgroundTaskIdentifier = .invalid
  private var cover: UIView?
  private let fm = FileManager.default
  private let jobs: FlutterMethodChannel
  private let privateRoot: URL
  private let cacheRoot: URL
  private let selection: URL
  private let ledger: URL
  private let interruptedLedger: URL
  private var incoming: [String: [String: Any]] = [:]
  private var incomingLeases = Set<String>()
  private var incomingChannel: FlutterMethodChannel?

  init(controller: FlutterViewController) throws {
    host = controller
    jobs = FlutterMethodChannel(name: "future_notes/jobs", binaryMessenger: controller.binaryMessenger)
    privateRoot = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("FutureNotes", isDirectory: true)
    cacheRoot = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("attachment-previews", isDirectory: true)
    selection = privateRoot.appendingPathComponent("library.json")
    ledger = privateRoot.appendingPathComponent("jobs.json")
    interruptedLedger = privateRoot.appendingPathComponent("interrupted-jobs.json")
    super.init()
    try protectDirectory(privateRoot)
    try protectDirectory(cacheRoot)
    install("future_notes/documents", controller) { [weak self] call, result in self?.documentCall(call, result) }
    install("future_notes/files", controller) { [weak self] call, result in self?.fileCall(call, result) }
    let incomingChannel = FlutterMethodChannel(name: "future_notes/incoming_shares", binaryMessenger: controller.binaryMessenger)
    self.incomingChannel = incomingChannel
    incomingChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      self.queue.async { self.reply(result) { try self.incomingCall(call) } }
    }
    install("future_notes/private_drafts", controller) { [weak self] call, result in
      guard let self = self else { return }
      self.queue.async { self.reply(result) { try self.draftCall(call) } }
    }
    jobs.setMethodCallHandler { [weak self] call, result in self?.jobCall(call, result) }
    NotificationCenter.default.addObserver(self, selector: #selector(coverSnapshot), name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(uncoverSnapshot), name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  private func install(_ name: String, _ controller: FlutterViewController, _ handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler(handler); channels.append(channel)
  }
  private func failure(_ message: String) -> NSError { NSError(domain: "FutureNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  private func reply(_ result: @escaping FlutterResult, _ work: () throws -> Any?) {
    do { let value = try work(); DispatchQueue.main.async { result(value) } }
    catch { DispatchQueue.main.async { result(FlutterError(code: "native_document_failed", message: "The selected document operation failed. Existing material was retained.", details: nil)) } }
  }
  private func protectDirectory(_ url: URL) throws {
    try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var value = url; var flags = URLResourceValues(); flags.isExcludedFromBackup = true
    try value.setResourceValues(flags)
  }
  private func atomic(_ data: Data, _ url: URL) throws {
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var value = url; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try value.setResourceValues(flags)
  }
  private func readPrivate(_ url: URL, limit: Int) throws -> Data? {
    if !fm.fileExists(atPath: url.path) { return nil }
    let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? limit + 1
    if size > limit { throw failure("Private record exceeds its limit.") }
    return try Data(contentsOf: url)
  }
  private func name(_ value: Any?) throws -> String {
    guard let value = value as? String, !value.isEmpty, value.count <= 240, value != ".", value != "..", !value.contains("/"), !value.contains("\\"), !value.unicodeScalars.contains(where: { $0.value < 32 }) else { throw failure("Invalid document name.") }
    return value
  }
  private func root(_ token: String) throws -> URL {
    if let value = roots[token] { return value }
    guard let data = Data(base64Encoded: token) else { throw failure("Invalid bookmark.") }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale, url.startAccessingSecurityScopedResource() else { throw failure("Select the folder again.") }
    do {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey, .volumeIsLocalKey])
      guard values.isDirectory == true, values.isUbiquitousItem != true, values.volumeIsLocal == true else { throw failure("Select a local device folder.") }
      roots[token] = url; return url
    } catch { url.stopAccessingSecurityScopedResource(); throw error }
  }
  private func owned(_ token: String, _ library: String) throws -> URL {
    let parent = try root(library).standardizedFileURL.resolvingSymlinksInPath()
    guard let entry = entries[token], entry.0 == library else { throw failure("Invalid document capability.") }
    let url = entry.1.standardizedFileURL
    let resolved = url.resolvingSymlinksInPath()
    guard url == resolved, resolved == parent || resolved.path.hasPrefix(parent.path + "/") else { throw failure("Document escaped the selected folder.") }
    return url
  }
  private func coordinate<T>(_ url: URL, writing: Bool = false, _ block: @escaping (URL) throws -> T) throws -> T {
    var coordination: NSError?
    var operation: Error?
    var output: T?
    let accessor: (URL) -> Void = { actual in do { output = try block(actual) } catch { operation = error } }
    let coordinator = NSFileCoordinator(filePresenter: nil)
    if writing { coordinator.coordinate(writingItemAt: url, options: [], error: &coordination, byAccessor: accessor) }
    else { coordinator.coordinate(readingItemAt: url, options: [], error: &coordination, byAccessor: accessor) }
    if let error = coordination { throw error }; if let error = operation { throw error }
    guard let value = output else { throw failure("Access was not acknowledged.") }; return value
  }
  private func metadata(_ url: URL, _ library: String) throws -> [String: Any] {
    let values = try url.resourceValues(forKeys: [.nameKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
    guard values.isSymbolicLink != true else { throw failure("Linked documents are unsupported.") }
    let key = library + "\n" + url.standardizedFileURL.path
    let token = entryKeys[key] ?? UUID().uuidString
    entryKeys[key] = token; entries[token] = (library, url)
    return ["token": token, "name": values.name ?? url.lastPathComponent, "directory": values.isDirectory == true,
      "length": values.fileSize.map { NSNumber(value: $0) as Any } ?? NSNull(), "modified": values.contentModificationDate.map { NSNumber(value: Int64($0.timeIntervalSince1970 * 1000)) as Any } ?? NSNull()]
  }
  private func source(_ url: URL, owner: String, scoped: Bool) throws -> [String: Any] {
    let identity: String
    if owner == "picked" { identity = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString() }
    else { identity = url.absoluteString }
    let handle = try FileHandle(forReadingFrom: url)
    var status = stat()
    guard fstat(handle.fileDescriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { handle.closeFile(); throw failure("A seekable native file is required.") }
    let lease = UUID().uuidString
    leases[lease] = (owner, url, handle, scoped)
    return ["lease": lease, "path": url.path, "identity": identity, "length": status.st_size, "name": url.lastPathComponent]
  }
  private func closeLease(_ lease: String, owner: String) {
    if let value = leases[lease], value.0 == owner {
      value.2.closeFile(); if value.3 { value.1.stopAccessingSecurityScopedResource() }; leases.removeValue(forKey: lease)
      if incomingLeases.remove(lease) != nil { cleanupIncomingFile(value.1) }
    }
  }

  private func incomingRoot() -> URL? {
    fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nativedevps.futurenotes")?.appendingPathComponent("IncomingShares", isDirectory: true)
  }
  private func ownsIncoming(_ url: URL) -> Bool {
    guard let root = incomingRoot() else { return false }
    let folder = url.deletingLastPathComponent()
    return folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL && UUID(uuidString: folder.lastPathComponent) != nil && url.lastPathComponent.hasPrefix("file-") && url.pathExtension == "bin"
  }
  private func cleanupIncomingFile(_ url: URL) {
    guard ownsIncoming(url) else { return }
    try? fm.removeItem(at: url)
    let folder = url.deletingLastPathComponent()
    if let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil), !entries.contains(where: { $0.pathExtension == "bin" }) {
      try? fm.removeItem(at: folder)
    }
  }
  private func incomingCall(_ call: FlutterMethodCall) throws -> Any? {
    guard let root = incomingRoot() else {
      if call.method == "pending" { return [] }
      throw failure("App Group is unavailable. Configure signing on a Mac.")
    }
    if call.method == "pending" {
      for folder in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
        guard UUID(uuidString: folder.lastPathComponent) != nil, incoming[folder.lastPathComponent] == nil,
          let receipt = try readPrivate(folder.appendingPathComponent("receipt.json"), limit: 2 * 1024 * 1024),
          let manifest = try JSONSerialization.jsonObject(with: receipt) as? [String: Any], manifest["version"] as? Int == 1,
          let id = manifest["id"] as? String, id == folder.lastPathComponent,
          let records = manifest["sources"] as? [[String: Any]], (1...128).contains(records.count) else { continue }
        var opened: [[String: Any]] = []
        do {
          for record in records {
            let file = try name(record["file"])
            let url = folder.appendingPathComponent(file)
            guard ownsIncoming(url), let length = record["length"] as? NSNumber, length.int64Value >= 0, length.int64Value <= 10 * 1024 * 1024 * 1024 else { throw failure("Invalid shared file.") }
            var value = try source(url, owner: "picked", scoped: false)
            guard (value["length"] as? NSNumber)?.int64Value == length.int64Value else { throw failure("Shared file changed.") }
            value["name"] = record["name"] as? String ?? "Shared file"
            if let lease = value["lease"] as? String { incomingLeases.insert(lease) }
            opened.append(value)
          }
          incoming[id] = ["id": id, "sources": opened]
        } catch {
          for item in opened { if let lease = item["lease"] as? String { closeLease(lease, owner: "picked") } }
          throw error
        }
      }
      return Array(incoming.values)
    }
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? String, UUID(uuidString: id) != nil else { throw failure("Invalid share receipt.") }
    let folder = root.appendingPathComponent(id, isDirectory: true)
    if call.method == "claim" {
      guard let batch = incoming[id], let sources = batch["sources"] as? [[String: Any]],
        let lease = args["lease"] as? String, let selected = sources.first(where: { $0["lease"] as? String == lease }),
        let ownedSource = leases[lease], ownedSource.0 == "picked", ownsIncoming(ownedSource.1),
        let data = try readPrivate(folder.appendingPathComponent("receipt.json"), limit: 2 * 1024 * 1024),
        var manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let records = manifest["sources"] as? [[String: Any]] else { throw failure("Shared file is unavailable.") }
      let remaining = sources.filter { $0["lease"] as? String != lease }
      manifest["sources"] = records.filter { $0["file"] as? String != ownedSource.1.lastPathComponent }
      let receipt = folder.appendingPathComponent("receipt.json")
      if remaining.isEmpty {
        try atomic(data, folder.appendingPathComponent("accepted.json"))
        try fm.removeItem(at: receipt)
        incoming.removeValue(forKey: id)
      } else {
        try atomic(JSONSerialization.data(withJSONObject: manifest), receipt)
        incoming[id] = ["id": id, "sources": remaining]
      }
      return selected
    }
    if call.method == "acknowledge" {
      let receipt = folder.appendingPathComponent("receipt.json")
      if fm.fileExists(atPath: receipt.path) { try fm.moveItem(at: receipt, to: folder.appendingPathComponent("accepted.json")) }
      incoming.removeValue(forKey: id)
      return nil
    }
    if call.method == "discard" {
      if let batch = incoming.removeValue(forKey: id), let sources = batch["sources"] as? [[String: Any]] {
        for item in sources { if let lease = item["lease"] as? String { closeLease(lease, owner: "picked") } }
      }
      let receipt = folder.appendingPathComponent("receipt.json")
      if fm.fileExists(atPath: receipt.path) { try fm.removeItem(at: receipt) }
      // Claimed files can still be owned by another job or its recovery record.
      if let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
        !entries.contains(where: { $0.pathExtension == "bin" }) { try fm.removeItem(at: folder) }
      return nil
    }
    throw failure("Unsupported share inbox action.")
  }
  private func documentCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if call.method == "selectLocalFolder" || call.method == "pickFile" || call.method == "pickFiles" {
      guard picker == nil, let host = host else { result(FlutterError(code: "picker_busy", message: "Finish the current picker first.", details: nil)); return }
      picker = result; pickingFolder = call.method == "selectLocalFolder"
      pickingMultiple = call.method == "pickFiles"
      let controller = UIDocumentPickerViewController(documentTypes: [pickingFolder ? "public.folder" : "public.item"], in: .open)
      controller.delegate = self; controller.allowsMultipleSelection = pickingMultiple; host.present(controller, animated: true); return
    }
    queue.async { self.reply(result) { try self.documentWork(call) } }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = picker; let exporting = exportingFile
    picker = nil; exportingFile = false; pickingMultiple = false; result?(exporting ? false : nil)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = picker else { return }; picker = nil
    if exportingFile { exportingFile = false; result(!urls.isEmpty); return }
    let folder = pickingFolder
    let multiple = pickingMultiple
    pickingMultiple = false
    queue.async {
      self.reply(result) {
        if folder {
          guard urls.count == 1, let url = urls.first, url.isFileURL, url.startAccessingSecurityScopedResource() else { throw self.failure("Access was not granted.") }
          defer { url.stopAccessingSecurityScopedResource() }
          let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey, .volumeIsLocalKey])
          guard values.isDirectory == true, values.isUbiquitousItem != true, values.volumeIsLocal == true else { throw self.failure("Select a local-device folder.") }
          return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()
        }
        guard !urls.isEmpty, multiple || urls.count == 1 else { throw self.failure("Choose attachment files.") }
        var opened: [[String: Any]] = []
        var seen = Set<URL>()
        do {
          for url in urls where seen.insert(url.standardizedFileURL).inserted {
            guard url.isFileURL, url.startAccessingSecurityScopedResource() else { throw self.failure("Access was not granted.") }
            do { opened.append(try self.source(url, owner: "picked", scoped: true)) }
            catch { url.stopAccessingSecurityScopedResource(); throw error }
          }
          if multiple { return opened }
          return opened[0]
        } catch {
          for value in opened { if let lease = value["lease"] as? String { self.closeLease(lease, owner: "picked") } }
          throw error
        }
      }
    }
  }
  private func documentWork(_ call: FlutterMethodCall) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "forgetPickedSource" {
      if let encoded = args["identity"] as? String, let data = Data(base64Encoded: encoded) {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale), ownsIncoming(url), !leases.values.contains(where: { $0.1 == url }) { cleanupIncomingFile(url) }
      }
      return nil
    }
    if call.method == "reopenPickedSource" {
      guard let encoded = args["identity"] as? String, let data = Data(base64Encoded: encoded) else { throw failure("Missing input bookmark.") }
      var stale = false
      let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
      if !stale && ownsIncoming(url) {
        let value = try source(url, owner: "picked", scoped: false)
        if let lease = value["lease"] as? String { incomingLeases.insert(lease) }
        return value
      }
      guard !stale, url.startAccessingSecurityScopedResource() else { throw failure("Select the input again.") }
      do { return try source(url, owner: "picked", scoped: true) } catch { url.stopAccessingSecurityScopedResource(); throw error }
    }
    if call.method == "closePickedSource" { closeLease(args["lease"] as? String ?? "", owner: "picked"); return nil }
    guard let library = args["library"] as? String else { throw failure("Missing library capability.") }
    if call.method == "root" { return try metadata(root(library), library) }
    if call.method == "closeSource" { closeLease(args["lease"] as? String ?? "", owner: library); return nil }
    let url = try owned(args["document"] as? String ?? "", library)
    switch call.method {
    case "stat": return try coordinate(url) { try self.metadata($0, library) }
    case "children": return try coordinate(url) { parent in
      let children = try self.fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [])
      if children.count > 10000 { throw self.failure("Inventory exceeds its limit.") }
      return try children.map { try self.metadata($0, library) }
    }
    case "create":
      let childName = try name(args["name"])
      return try coordinate(url, writing: true) { parent in
        let child = parent.appendingPathComponent(childName, isDirectory: args["directory"] as? Bool == true)
        if self.fm.fileExists(atPath: child.path) { throw self.failure("The exact name already exists.") }
        if args["directory"] as? Bool == true { try self.fm.createDirectory(at: child, withIntermediateDirectories: false) }
        else { let fd = Darwin.open(child.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR); guard fd >= 0 else { throw self.failure("Exclusive creation failed.") }; Darwin.close(fd) }
        return try self.metadata(child, library)
      }
    case "read":
      let offset = (args["offset"] as? NSNumber)?.int64Value ?? -1
      let length = (args["length"] as? NSNumber)?.intValue ?? -1
      guard offset >= 0, length >= 0, length <= 1048576 else { throw failure("Invalid read range.") }
      return try coordinate(url) { actual in let handle = try FileHandle(forReadingFrom: actual); defer { handle.closeFile() }; try handle.seek(toOffset: UInt64(offset)); return FlutterStandardTypedData(bytes: try handle.read(upToCount: length) ?? Data()) }
    case "append":
      let offset = (args["offset"] as? NSNumber)?.int64Value ?? -1
      guard let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data, offset >= 0, bytes.count <= 1048576 else { throw failure("Invalid write range.") }
      return try coordinate(url, writing: true) { actual in let handle = try FileHandle(forWritingTo: actual); defer { handle.closeFile() }; guard try handle.seekToEnd() == UInt64(offset) else { throw self.failure("Write offset changed.") }; try handle.write(contentsOf: bytes); return NSNull() }
    case "flush": return try coordinate(url, writing: true) { actual in let handle = try FileHandle(forWritingTo: actual); defer { handle.closeFile() }; try handle.synchronize(); return NSNull() }
    case "rename":
      let newName = try name(args["name"])
      guard url != (try root(library)) else { throw failure("Cannot rename the library root.") }
      return try coordinate(url.deletingLastPathComponent(), writing: true) { parent in
        let next = parent.appendingPathComponent(newName)
        guard !self.fm.fileExists(atPath: next.path) else { throw self.failure("Rename target exists.") }
        try self.fm.moveItem(at: url, to: next); return try self.metadata(next, library)
      }
    case "delete":
      guard url != (try root(library)) else { throw failure("Cannot remove the library root.") }
      return try coordinate(url, writing: true) { actual in
        if (try actual.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true && !(try self.fm.contentsOfDirectory(atPath: actual.path)).isEmpty { throw self.failure("Nonempty folder retained.") }
        try self.fm.removeItem(at: actual); return NSNull()
      }
    case "openSource": return try coordinate(url) { try self.source($0, owner: library, scoped: false) }
    default: throw failure("Unsupported document action.")
    }
  }

  private func fileCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "saveExport" || call.method == "shareExport" {
      do {
        guard picker == nil, let host = host, let path = args["path"] as? String else { throw failure("Finish the current picker first.") }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath().appendingPathComponent("prepared-exports", isDirectory: true)
        guard url == url.resolvingSymlinksInPath(), url.deletingLastPathComponent().deletingLastPathComponent() == cache,
              url.deletingLastPathComponent().lastPathComponent.hasPrefix("future-notes-export-"), fm.fileExists(atPath: url.path) else { throw failure("Unowned export.") }
        if call.method == "shareExport" {
          let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
          controller.popoverPresentationController?.sourceView = host.view
          controller.popoverPresentationController?.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
          controller.completionWithItemsHandler = { _, completed, _, error in
            if error != nil { result(FlutterError(code: "export_share_failed", message: "Sharing failed. The prepared export is retained.", details: nil)) }
            else { result(completed) }
          }
          host.present(controller, animated: true); return
        }
        picker = result; exportingFile = true
        let controller: UIDocumentPickerViewController
        if #available(iOS 14.0, *) { controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
        else { controller = UIDocumentPickerViewController(url: url, in: .exportToService) }
        controller.delegate = self; host.present(controller, animated: true)
      } catch { result(FlutterError(code: "export_save_failed", message: "The file could not be saved. The prepared export is still available.", details: nil)) }
      return
    }
    if call.method == "openFile" {
      do {
        guard let path = args["path"] as? String, let host = host else { throw failure("Attachment unavailable.") }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(cacheRoot.path + "/"), fm.fileExists(atPath: url.path) else { throw failure("Unowned attachment.") }
        let controller = UIDocumentInteractionController(url: url); interaction = controller
        guard controller.presentOpenInMenu(from: CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1), in: host.view, animated: true) else { throw failure("No application can open this attachment.") }
        result(nil)
      } catch { result(FlutterError(code: "external_open_failed", message: "This attachment could not be opened externally.", details: nil)) }
      return
    }
    if call.method == "revokeFiles" { interaction?.dismissMenu(animated: false); interaction = nil; result(nil); return }
    queue.async { self.reply(result) {
      switch call.method {
      case "cacheRoot": return self.cacheRoot.path
      case "privateRoot": return self.privateRoot.path
      case "readLibrarySelection": return try self.readPrivate(self.selection, limit: 65536).flatMap { String(data: $0, encoding: .utf8) }
      case "writeLibrarySelection":
        guard let json = args["json"] as? String, let data = json.data(using: .utf8), data.count <= 65536 else { throw self.failure("Invalid selection record.") }
        _ = try JSONSerialization.jsonObject(with: data); try self.atomic(data, self.selection); return nil
      default: throw self.failure("Unsupported file action.")
      }
    } }
  }
  private func draftKey() throws -> SymmetricKey {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "FutureNotes.private-draft.v1", kSecAttrAccount as String: Bundle.main.bundleIdentifier ?? "FutureNotes", kSecAttrSynchronizable as String: false]
    var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &value)
    if status == errSecSuccess, let bytes = value as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
    guard status == errSecItemNotFound else { throw failure("Protected recovery key unavailable.") }
    let key = SymmetricKey(size: .bits256); let bytes = key.withUnsafeBytes { Data($0) }
    var add = query; add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw failure("Recovery key could not be created.") }; return key
  }
  private func draftCall(_ call: FlutterMethodCall) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let library = args["library"] as? String, library.utf8.count <= 4096 else { throw failure("Missing recovery identity.") }
    let hash = SHA256.hash(data: Data(library.utf8)).map { String(format: "%02x", $0) }.joined()
    let url = privateRoot.appendingPathComponent("draft-\(hash).bin")
    let aad = Data(("future-notes-private-draft-v1:" + library).utf8)
    switch call.method {
    case "discard": if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }; return nil
    case "read":
      guard let bytes = try readPrivate(url, limit: 32 * 1024 * 1024 + 64) else { return nil }
      let value = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: draftKey(), authenticating: aad)
      guard let text = String(data: value, encoding: .utf8) else { throw failure("Invalid recovery encoding.") }; return text
    case "write":
      guard let text = args["json"] as? String, let bytes = text.data(using: .utf8), bytes.count <= 32 * 1024 * 1024 else { throw failure("Recovery exceeds its limit.") }
      _ = try JSONSerialization.jsonObject(with: bytes)
      guard let encrypted = try AES.GCM.seal(bytes, using: draftKey(), authenticating: aad).combined else { throw failure("Recovery encryption failed.") }
      try atomic(encrypted, url); return nil
    default: throw failure("Unsupported recovery action.")
    }
  }
  private func jobCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    do {
      if call.method == "interruptedJobs" {
        var records: [String: [String: Any]] = [:]
        for url in [interruptedLedger, ledger] {
          if let bytes = try readPrivate(url, limit: 2 * 1024 * 1024), let values = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] {
            for value in values { guard let id = value["id"] as? String else { throw failure("Invalid job identity.") }; records[id] = value }
          }
        }
        let bytes = try JSONSerialization.data(withJSONObject: Array(records.values))
        guard bytes.count <= 2 * 1024 * 1024 else { throw failure("Job recovery exceeds its limit.") }
        try atomic(bytes, interruptedLedger); result(String(data: bytes, encoding: .utf8)); return
      }
      if call.method == "acknowledgeInterrupted" || call.method == "dismissInterruptedNotification" {
        guard let args = call.arguments as? [String: Any], let ids = args["ids"] as? [String], ids.count <= 10000,
          ids.allSatisfy({ !$0.isEmpty && $0.count <= 128 }) else { throw failure("Invalid task identity.") }
        for url in [interruptedLedger, ledger] {
          if let bytes = try readPrivate(url, limit: 2 * 1024 * 1024), let values = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] {
            let retained = values.compactMap { value -> [String: Any]? in
              guard let id = value["id"] as? String else { return value }
              if !ids.contains(id) { return value }
              if call.method == "acknowledgeInterrupted" { return nil }
              var hidden = value; hidden["notificationDismissed"] = true; return hidden
            }
            try atomic(JSONSerialization.data(withJSONObject: retained), url)
          }
        }
        result(nil); return
      }
      guard call.method == "update", let args = call.arguments as? [String: Any], let values = args["jobs"] as? [[String: Any]], values.count <= 10000 else { throw failure("Invalid job update.") }
      // No passwords or plaintext are persisted. Expiration requests the same
      // safe cancellation used by the foreground UI; no new writer is created.
      try atomic(JSONSerialization.data(withJSONObject: values), ledger)
      if values.isEmpty { endBackground() }
      else if background == .invalid {
        background = UIApplication.shared.beginBackgroundTask(withName: "Future Notes attachment work") { [weak self] in self?.jobs.invokeMethod("timeout", arguments: nil); self?.endBackground() }
        if background == .invalid { jobs.invokeMethod("cancelSafeJobs", arguments: nil); throw failure("Background time unavailable.") }
      }
      let thermal: Int
      switch ProcessInfo.processInfo.thermalState { case .nominal: thermal = 0; case .fair: thermal = 1; case .serious: thermal = 3; case .critical: thermal = 4; @unknown default: thermal = 4 }
      result(["processors": ProcessInfo.processInfo.activeProcessorCount, "availableBytes": os_proc_available_memory(), "processCpu": 0.0, "systemCpu": 0.0, "thermal": thermal, "detected": false])
    } catch { result(FlutterError(code: "job_host_failed", message: "Background time is unavailable. Keep the app open and retry unfinished work.", details: nil)) }
  }
  private func endBackground() { if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid } }
  @objc private func coverSnapshot() {
    guard cover == nil, let window = host?.view.window else { return }
    let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial)); view.frame = window.bounds; view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.isUserInteractionEnabled = true
    window.addSubview(view); cover = view
  }
  @objc private func uncoverSnapshot() { cover?.removeFromSuperview(); cover = nil; incomingChannel?.invokeMethod("changed", arguments: nil) }
  deinit {
    NotificationCenter.default.removeObserver(self)
    for value in leases.values { value.2.closeFile(); if value.3 { value.1.stopAccessingSecurityScopedResource() } }
    for url in roots.values { url.stopAccessingSecurityScopedResource() }
  }
}
