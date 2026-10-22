import Flutter
import UIKit
import Foundation
import CryptoKit
import Security
import Darwin
import os
import UserNotifications

/// Stable channel failures; native errors and paths never cross the channel.
private enum DocumentFailure: String, Error {
  case nameExists = "name_exists"
  case permissionRevoked = "permission_revoked"
  case missingDocument = "missing_document"
  case fullDisk = "full_disk"
  case nativeFailure = "native_document_failed"

  var message: String {
    switch self {
    case .nameExists: return "A document with this name already exists."
    case .permissionRevoked: return "Folder access is no longer available. Select the folder again."
    case .missingDocument: return "The selected document is no longer available."
    case .fullDisk: return "The selected storage does not have enough free space."
    case .nativeFailure: return "The selected document operation failed. Existing material was retained."
    }
  }

  static func classify(_ error: Error) -> DocumentFailure {
    if let failure = error as? DocumentFailure { return failure }
    let native = error as NSError
    if native.domain == NSPOSIXErrorDomain {
      switch Int32(native.code) {
      case EEXIST: return .nameExists
      case EACCES, EPERM, EROFS: return .permissionRevoked
      case ENOENT: return .missingDocument
      case ENOSPC, EDQUOT: return .fullDisk
      default: break
      }
    }
    if native.domain == NSCocoaErrorDomain {
      switch native.code {
      case NSFileWriteFileExistsError: return .nameExists
      case NSFileReadNoPermissionError, NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError: return .permissionRevoked
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .missingDocument
      case NSFileWriteOutOfSpaceError: return .fullDisk
      default: break
      }
    }
    return .nativeFailure
  }
}

/// File-presenter callbacks only request metadata reconciliation. They do not
/// grant write authority or create another storage/job owner.
private final class LibraryPresenter: NSObject, NSFilePresenter {
  let presentedItemURL: URL?
  let presentedItemOperationQueue: OperationQueue
  private let changed: () -> Void

  init(url: URL, changed: @escaping () -> Void) {
    presentedItemURL = url
    self.changed = changed
    presentedItemOperationQueue = OperationQueue()
    presentedItemOperationQueue.maxConcurrentOperationCount = 1
    super.init()
  }

  func presentedItemDidChange() { changed() }
  func presentedItemDidMove(to newURL: URL) { changed() }
  func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
    changed(); completionHandler(nil)
  }
  func presentedSubitemDidAppear(at url: URL) { changed() }
  func presentedSubitemDidChange(at url: URL) { changed() }
  func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
  func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
    changed(); completionHandler(nil)
  }
}

/// Owns only Future Notes job notifications. Job execution and recovery remain
/// with the existing Dart coordinator and protected native ledgers.
private final class JobNotifications: NSObject, UNUserNotificationCenterDelegate {
  private struct Record {
    let id: String
    let fileName: String
    let operation: String
    let phase: String
    let detail: String
    let cancellable: Bool
    let bytes: Int64
    let total: Int64
    let interrupted: Bool
  }

  private struct Rendered {
    let record: Record
    let content: UNMutableNotificationContent
    let signature: String
  }

  private let center = UNUserNotificationCenter.current()
  private let queue = DispatchQueue(label: "future-notes.notifications")
  private weak var previousDelegate: UNUserNotificationCenterDelegate?
  private weak var channel: FlutterMethodChannel?
  private let dismissed: (String) -> Void
  private var active: [String: Record] = [:]
  private var interrupted: [String: Record] = [:]
  private var activeLoaded = false
  private var interruptedLoaded = false
  private var enumerationRemaining = 2
  private var owned = Set<String>()
  private var posted: [String: String] = [:]
  private var failed: [String: String] = [:]
  private var attempted: [String: UInt64] = [:]
  private var attemptSequence: UInt64 = 0
  private var inFlight: (id: String, signature: String)?
  private var pendingTap: String?
  private var pendingDismissals = Set<String>()
  private var closed = false
  private var lastPump = Date.distantPast
  private var permissionRequesting = false
  private var permissionRequested = false
  private var authorization: UNAuthorizationStatus?
  private var settingsInFlight = false
  private var retryFailuresOnSettings = false
  private var scheduled: DispatchWorkItem?
  private var activeObserver: NSObjectProtocol?

  private static let prefix = "future-notes.job."
  private static let owner = "future-notes.jobs.v1"
  private static let cancellableCategory = "future-notes.jobs.cancellable"
  private static let reviewCategory = "future-notes.jobs.review"
  private static let interruptedCategory = "future-notes.jobs.interrupted"
  private static let cancelAction = "future-notes.jobs.cancel"

  init(channel: FlutterMethodChannel, dismissed: @escaping (String) -> Void) {
    self.channel = channel
    self.dismissed = dismissed
    super.init()
    previousDelegate = center.delegate
    center.delegate = self
    activeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.queue.async {
        self?.readAuthorization(resumeRetry: true)
      }
    }
    center.getNotificationCategories { [weak self] existing in
      guard let self = self else { return }
      let cancel = UNNotificationAction(
        identifier: Self.cancelAction,
        title: "Cancel",
        options: [.destructive]
      )
      let cancellable = UNNotificationCategory(
        identifier: Self.cancellableCategory,
        actions: [cancel],
        intentIdentifiers: [],
        options: []
      )
      let review = UNNotificationCategory(
        identifier: Self.reviewCategory,
        actions: [],
        intentIdentifiers: [],
        options: []
      )
      let interrupted = UNNotificationCategory(
        identifier: Self.interruptedCategory,
        actions: [],
        intentIdentifiers: [],
        options: [.customDismissAction]
      )
      self.center.setNotificationCategories(
        existing.union([cancellable, review, interrupted])
      )
    }
    center.getPendingNotificationRequests { [self] requests in
      queue.async { [self] in
        self.acceptExisting(requests.map(\.content), requests.map(\.identifier))
      }
    }
    center.getDeliveredNotifications { [self] notifications in
      queue.async { [self] in
        self.acceptExisting(
          notifications.map { $0.request.content },
          notifications.map { $0.request.identifier }
        )
      }
    }
  }

  func updateActive(_ values: [[String: Any]]) {
    queue.async { [weak self] in
      guard let self = self else { return }
      var records: [String: Record] = [:]
      for value in values {
        if let record = self.record(value, interrupted: false) { records[record.id] = record }
      }
      self.active = records
      self.activeLoaded = true
      self.schedulePump()
    }
  }

  func restoreInterrupted(_ values: [[String: Any]]) {
    queue.async { [weak self] in
      guard let self = self else { return }
      var records: [String: Record] = [:]
      for value in values where value["notificationDismissed"] as? Bool != true {
        if let record = self.record(value, interrupted: true) { records[record.id] = record }
      }
      self.interrupted = records
      self.interruptedLoaded = true
      let dismissals = self.pendingDismissals.intersection(records.keys)
      self.pendingDismissals.subtract(dismissals)
      for id in dismissals {
        DispatchQueue.main.async { [weak self] in self?.dismissed(id) }
      }
      self.schedulePump()
    }
  }

  func takePendingTap() -> String? {
    queue.sync {
      defer { pendingTap = nil }
      return pendingTap
    }
  }

  func tearDown() {
    let identifiers: [String] = queue.sync {
      closed = true
      scheduled?.cancel()
      scheduled = nil
      active.removeAll()
      interrupted.removeAll()
      pendingTap = nil
      pendingDismissals.removeAll()
      let ids = owned.union(inFlight.map { [$0.id] } ?? []).map { Self.prefix + $0 }
      owned.removeAll()
      posted.removeAll()
      failed.removeAll()
      attempted.removeAll()
      retryFailuresOnSettings = false
      return ids
    }
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
    if let observer = activeObserver { NotificationCenter.default.removeObserver(observer) }
    activeObserver = nil
    if (center.delegate as AnyObject?) === self { center.delegate = previousDelegate }
  }

  private func record(_ value: [String: Any], interrupted: Bool) -> Record? {
    guard let id = value["id"] as? String,
      !id.isEmpty, id.count <= 128 else { return nil }
    return Record(
      id: id,
      fileName: display(value["fileName"] as? String, fallback: "Background task"),
      operation: display(value["operation"] as? String, fallback: "work"),
      phase: display(value["phase"] as? String, fallback: interrupted ? "interrupted" : "active"),
      detail: display(value["detail"] as? String, fallback: ""),
      cancellable: value["cancellable"] as? Bool == true,
      bytes: (value["bytes"] as? NSNumber)?.int64Value ?? 0,
      total: (value["total"] as? NSNumber)?.int64Value ?? 0,
      interrupted: interrupted
    )
  }

  private func display(_ value: String?, fallback: String) -> String {
    let source: String = value ?? fallback
    let safe = source.unicodeScalars.filter {
      !CharacterSet.controlCharacters.contains($0) && $0.value != 0x2f && $0.value != 0x5c
    }
    let text = String(String.UnicodeScalarView(safe)).trimmingCharacters(in: .whitespacesAndNewlines)
    return String((text.isEmpty ? fallback : text).prefix(160))
  }

  private func acceptExisting(_ contents: [UNNotificationContent], _ identifiers: [String]) {
    var remove: [String] = []
    for (content, identifier) in zip(contents, identifiers) {
      guard let id = ownedID(identifier, content) else { continue }
      if closed { remove.append(identifier); continue }
      owned.insert(id)
      if let signature = content.userInfo["signature"] as? String { posted[id] = signature }
    }
    if !remove.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: remove)
      center.removeDeliveredNotifications(withIdentifiers: remove)
    }
    enumerationRemaining -= 1
    schedulePump()
  }

  private func schedulePump() {
    guard !closed, scheduled == nil, inFlight == nil else { return }
    let delay = max(0, 1 - Date().timeIntervalSince(lastPump))
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.scheduled = nil
      self.lastPump = Date()
      self.pump()
    }
    scheduled = work
    queue.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func desired() -> [String: Rendered] {
    var values: [String: Record] = interrupted
    for (id, record) in active { values[id] = record }
    return values.mapValues(render)
  }

  private func pump() {
    guard !closed, activeLoaded, interruptedLoaded, enumerationRemaining == 0,
      inFlight == nil else { return }
    let wanted = desired()
    let stale = owned.filter { wanted[$0] == nil }
    if !stale.isEmpty {
      let identifiers = stale.map { Self.prefix + $0 }
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
      center.removeDeliveredNotifications(withIdentifiers: identifiers)
      for id in stale {
        owned.remove(id)
        posted.removeValue(forKey: id)
        failed.removeValue(forKey: id)
        attempted.removeValue(forKey: id)
      }
    }
    let eligible = wanted.values.filter {
      posted[$0.record.id] != $0.signature && failed[$0.record.id] != $0.signature
    }
    guard let next = eligible.min(by: {
      let left = attempted[$0.record.id] ?? 0
      let right = attempted[$1.record.id] ?? 0
      return left == right ? $0.record.id < $1.record.id : left < right
    }) else { return }
    switch authorization {
    case .authorized?, .provisional?:
      add(next)
    case .denied?, .notDetermined?:
      if authorization == .notDetermined { requestAuthorizationIfAppropriate() }
    case nil:
      readAuthorization()
    default:
      if #available(iOS 14.0, *), authorization == .ephemeral { add(next) }
    }
  }

  private func render(_ record: Record) -> Rendered {
    let content = UNMutableNotificationContent()
    content.title = record.interrupted ? "Unfinished work" : record.fileName
    if record.interrupted {
      content.body = "\(record.fileName) was interrupted. Tap to review recovery."
      content.categoryIdentifier = Self.interruptedCategory
    } else if #available(iOS 15.0, *) {
      var progress = record.detail.isEmpty ? record.phase : record.detail
      if record.total > 0 {
        let percent = max(0, min(100, Int((Double(record.bytes) / Double(record.total)) * 100)))
        progress += " · \(percent)% (\(record.bytes)/\(record.total) bytes)"
      } else if record.bytes > 0 {
        progress += " · \(record.bytes) bytes"
      }
      content.body = "\(record.operation): \(progress)"
      content.categoryIdentifier = record.cancellable ? Self.cancellableCategory : Self.reviewCategory
    } else {
      content.body = "\(record.operation): Tap for live progress."
      content.categoryIdentifier = record.cancellable ? Self.cancellableCategory : Self.reviewCategory
    }
    if #available(iOS 15.0, *) { content.interruptionLevel = .passive }
    content.threadIdentifier = Self.owner
    let rendered = [content.title, content.body, content.categoryIdentifier].joined(separator: "\n")
    let signature = SHA256.hash(data: Data(rendered.utf8)).map { String(format: "%02x", $0) }.joined()
    content.userInfo = ["owner": Self.owner, "job": record.id, "signature": signature]
    return Rendered(record: record, content: content, signature: signature)
  }

  private func add(_ rendered: Rendered) {
    guard !closed, inFlight == nil else { return }
    let id = rendered.record.id
    attemptSequence += 1
    attempted[id] = attemptSequence
    inFlight = (id, rendered.signature)
    let request = UNNotificationRequest(
      identifier: Self.prefix + id,
      content: rendered.content,
      trigger: nil
    )
    center.add(request) { [self] error in
      queue.async { [self] in
        let latest = self.desired()[id]
        if self.closed || latest == nil {
          self.remove(id)
        } else if error == nil {
          self.owned.insert(id)
          self.posted[id] = rendered.signature
          self.failed.removeValue(forKey: id)
        } else {
          self.failed[id] = rendered.signature
        }
        self.inFlight = nil
        self.schedulePump()
      }
    }
  }

  private func remove(_ id: String) {
    let identifier = Self.prefix + id
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    owned.remove(id)
    posted.removeValue(forKey: id)
    failed.removeValue(forKey: id)
    attempted.removeValue(forKey: id)
  }

  private func readAuthorization(resumeRetry: Bool = false) {
    if resumeRetry { retryFailuresOnSettings = true }
    guard !settingsInFlight else { return }
    settingsInFlight = true
    center.getNotificationSettings { [self] settings in
      queue.async { [self] in
        self.settingsInFlight = false
        guard !self.closed else { return }
        let previous = self.authorization
        self.authorization = settings.authorizationStatus
        let retryFailures = self.retryFailuresOnSettings
        self.retryFailuresOnSettings = false
        if retryFailures { self.failed.removeAll() }
        var wasAllowed = previous == .authorized || previous == .provisional
        var isAllowed = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional
        if #available(iOS 14.0, *) {
          wasAllowed = wasAllowed || previous == .ephemeral
          isAllowed = isAllowed || settings.authorizationStatus == .ephemeral
        }
        if previous != nil, !wasAllowed, isAllowed {
          self.posted.removeAll()
        }
        self.schedulePump()
      }
    }
  }

  private func requestAuthorizationIfAppropriate() {
    guard !active.isEmpty, !permissionRequesting, !permissionRequested else { return }
    permissionRequesting = true
    DispatchQueue.main.async { [self] in
      guard UIApplication.shared.applicationState == .active,
        queue.sync(execute: { !closed && !active.isEmpty }) else {
        queue.async { [self] in self.permissionRequesting = false }
        return
      }
      queue.sync { permissionRequested = true }
      center.requestAuthorization(options: [.alert]) { [self] granted, _ in
        queue.async { [self] in
          self.permissionRequesting = false
          guard !self.closed else { return }
          self.authorization = granted ? .authorized : .denied
          self.schedulePump()
        }
      }
    }
  }

  private func ownedID(_ identifier: String, _ content: UNNotificationContent) -> String? {
    guard content.userInfo["owner"] as? String == Self.owner,
      let id = content.userInfo["job"] as? String,
      !id.isEmpty, id.count <= 128,
      identifier == Self.prefix + id else { return nil }
    return id
  }

  private func owns(_ notification: UNNotification) -> String? {
    ownedID(notification.request.identifier, notification.request.content)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if owns(notification) != nil { completionHandler([]); return }
    if let previous = previousDelegate,
      previous.responds(to: #selector(userNotificationCenter(_:willPresent:withCompletionHandler:))) {
      previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
    } else { completionHandler([]) }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let id = owns(response.notification) else {
      if let previous = previousDelegate,
        previous.responds(to: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:))) {
        previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
      } else { completionHandler() }
      return
    }
    queue.async { [weak self] in
      guard let self = self else { DispatchQueue.main.async { completionHandler() }; return }
      guard !self.closed else { DispatchQueue.main.async { completionHandler() }; return }
      if response.actionIdentifier == Self.cancelAction,
        response.notification.request.content.categoryIdentifier == Self.cancellableCategory,
        let record = self.active[id], record.cancellable {
        DispatchQueue.main.async { [weak self] in
          self?.channel?.invokeMethod("cancelJob", arguments: ["id": id])
          completionHandler()
        }
      } else if response.actionIdentifier == UNNotificationDismissActionIdentifier,
        response.notification.request.content.categoryIdentifier == Self.interruptedCategory {
        if self.interruptedLoaded {
          if self.interrupted[id] != nil {
            DispatchQueue.main.async { [weak self] in self?.dismissed(id) }
          }
        } else {
          self.pendingDismissals.insert(id)
        }
        DispatchQueue.main.async { completionHandler() }
      } else {
        self.pendingTap = id
        DispatchQueue.main.async { [weak self] in
          self?.channel?.invokeMethod("jobNotification", arguments: nil)
          completionHandler()
        }
      }
    }
  }
}

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
  private var jobNotifications: JobNotifications?
  private let privateRoot: URL
  private let cacheRoot: URL
  private let selection: URL
  private let ledger: URL
  private let interruptedLedger: URL
  private var incoming: [String: [String: Any]] = [:]
  private var incomingLeases = Set<String>()
  private var incomingChannel: FlutterMethodChannel?
  private var libraryChannel: FlutterMethodChannel?
  private var presenters: [String: LibraryPresenter] = [:]

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
    let libraryChannel = FlutterMethodChannel(name: "future_notes/library_events", binaryMessenger: controller.binaryMessenger)
    self.libraryChannel = libraryChannel
    libraryChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      self.queue.async { self.reply(result) { try self.libraryEventCall(call) } }
    }
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
    jobNotifications = JobNotifications(channel: jobs) { [weak self] id in
      self?.dismissInterruptedNotification(id)
    }
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
    catch {
      let failure = DocumentFailure.classify(error)
      DispatchQueue.main.async { result(FlutterError(code: failure.rawValue, message: failure.message, details: nil)) }
    }
  }
  private func libraryEventCall(_ call: FlutterMethodCall) throws -> Any? {
    guard let args = call.arguments as? [String: Any], let library = args["library"] as? String else { throw failure("Missing library capability.") }
    switch call.method {
    case "watch":
      if presenters[library] == nil {
        let url = try root(library)
        let presenter = LibraryPresenter(url: url) { [weak self] in self?.libraryChanged(library) }
        presenters[library] = presenter
        NSFileCoordinator.addFilePresenter(presenter)
      }
    case "unwatch":
      if let presenter = presenters.removeValue(forKey: library) { NSFileCoordinator.removeFilePresenter(presenter) }
    default: throw failure("Unsupported library event action.")
    }
    return nil
  }
  private func libraryChanged(_ library: String) {
    queue.async { [weak self] in
      guard let self = self, self.presenters[library] != nil else { return }
      DispatchQueue.main.async { [weak self] in self?.libraryChannel?.invokeMethod("changed", arguments: library) }
    }
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
    guard !stale, url.startAccessingSecurityScopedResource() else { throw DocumentFailure.permissionRevoked }
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
  private func posixRead(_ descriptor: Int32, offset: Int64, length: Int) throws -> Data {
    guard offset <= Int64.max - Int64(length) else { throw failure("Invalid read range.") }
    if length == 0 { return Data() }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }
    var received = 0
    while received < length {
      let count = Darwin.pread(
        descriptor,
        buffer.advanced(by: received),
        length - received,
        off_t(offset + Int64(received))
      )
      if count < 0 {
        if errno == EINTR { continue }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
      }
      if count == 0 { break }
      received += count
    }
    return Data(bytes: buffer, count: received)
  }
  private func posixAppend(_ descriptor: Int32, offset: Int64, bytes: Data) throws {
    var end: off_t = -1
    repeat { end = Darwin.lseek(descriptor, 0, SEEK_END) } while end < 0 && errno == EINTR
    if end < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil) }
    guard end == off_t(offset) else { throw failure("Write offset changed.") }
    try bytes.withUnsafeBytes { source in
      var written = 0
      while written < source.count {
        let count = Darwin.write(descriptor, source.baseAddress!.advanced(by: written), source.count - written)
        if count < 0 {
          if errno == EINTR { continue }
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        if count == 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: nil) }
        written += count
      }
    }
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
        if self.fm.fileExists(atPath: child.path) { throw DocumentFailure.nameExists }
        if args["directory"] as? Bool == true { try self.fm.createDirectory(at: child, withIntermediateDirectories: false) }
        else { let fd = Darwin.open(child.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR); guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil) }; Darwin.close(fd) }
        return try self.metadata(child, library)
      }
    case "read":
      let offset = (args["offset"] as? NSNumber)?.int64Value ?? -1
      let length = (args["length"] as? NSNumber)?.intValue ?? -1
      guard offset >= 0, length >= 0, length <= 1048576,
        offset <= Int64.max - Int64(max(length, 0)) else { throw failure("Invalid read range.") }
      return try coordinate(url) { actual in
        let handle = try FileHandle(forReadingFrom: actual)
        defer { handle.closeFile() }
        let bytes: Data
        if #available(iOS 13.4, *) {
          try handle.seek(toOffset: UInt64(offset))
          bytes = try handle.read(upToCount: length) ?? Data()
        } else {
          bytes = try self.posixRead(handle.fileDescriptor, offset: offset, length: length)
        }
        return FlutterStandardTypedData(bytes: bytes)
      }
    case "append":
      let offset = (args["offset"] as? NSNumber)?.int64Value ?? -1
      guard let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data, offset >= 0, bytes.count <= 1048576 else { throw failure("Invalid write range.") }
      return try coordinate(url, writing: true) { actual in
        let handle = try FileHandle(forWritingTo: actual)
        defer { handle.closeFile() }
        if #available(iOS 13.4, *) {
          guard try handle.seekToEnd() == UInt64(offset) else { throw self.failure("Write offset changed.") }
          try handle.write(contentsOf: bytes)
        } else {
          try self.posixAppend(handle.fileDescriptor, offset: offset, bytes: bytes)
        }
        return NSNull()
      }
    case "flush": return try coordinate(url, writing: true) { actual in let handle = try FileHandle(forWritingTo: actual); defer { handle.closeFile() }; try handle.synchronize(); return NSNull() }
    case "rename":
      let newName = try name(args["name"])
      guard url != (try root(library)) else { throw failure("Cannot rename the library root.") }
      return try coordinate(url.deletingLastPathComponent(), writing: true) { parent in
        let next = parent.appendingPathComponent(newName)
        guard !self.fm.fileExists(atPath: next.path) else { throw DocumentFailure.nameExists }
        try self.fm.moveItem(at: url, to: next); return try self.metadata(next, library)
      }
    case "delete":
      guard url != (try root(library)) else { throw failure("Cannot remove the library root.") }
      return try coordinate(url, writing: true) { actual in
        if (try actual.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
          if !(try self.fm.contentsOfDirectory(atPath: actual.path)).isEmpty {
            throw self.failure("Nonempty folder retained.")
          }
        }
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
      case "readSettings":
        guard let data = try self.readPrivate(self.privateRoot.appendingPathComponent("settings-v1.json"), limit: 65536) else { return nil }
        guard let json = String(data: data, encoding: .utf8) else { throw self.failure("Invalid settings record.") }
        return json
      case "writeSettings":
        guard let json = args["json"] as? String, let data = json.data(using: .utf8), data.count <= 65536,
          (try JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw self.failure("Invalid settings record.") }
        try self.atomic(data, self.privateRoot.appendingPathComponent("settings-v1.json")); return nil
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
      if call.method == "takeNotification" {
        result(jobNotifications?.takePendingTap()); return
      }
      if call.method == "interruptedJobs" {
        var records: [String: [String: Any]] = [:]
        for url in [interruptedLedger, ledger] {
          if let bytes = try readPrivate(url, limit: 2 * 1024 * 1024), let values = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] {
            for value in values { guard let id = value["id"] as? String else { throw failure("Invalid job identity.") }; records[id] = value }
          }
        }
        let bytes = try JSONSerialization.data(withJSONObject: Array(records.values))
        guard bytes.count <= 2 * 1024 * 1024 else { throw failure("Job recovery exceeds its limit.") }
        try atomic(bytes, interruptedLedger)
        jobNotifications?.restoreInterrupted(Array(records.values))
        result(String(data: bytes, encoding: .utf8)); return
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
        jobNotifications?.restoreInterrupted(try interruptedRecords())
        result(nil); return
      }
      guard call.method == "update", let args = call.arguments as? [String: Any], let values = args["jobs"] as? [[String: Any]], values.count <= 10000 else { throw failure("Invalid job update.") }
      // No passwords or plaintext are persisted. Expiration requests the same
      // safe cancellation used by the foreground UI; no new writer is created.
      try atomic(JSONSerialization.data(withJSONObject: values), ledger)
      jobNotifications?.updateActive(values)
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
  private func interruptedRecords() throws -> [[String: Any]] {
    guard let bytes = try readPrivate(interruptedLedger, limit: 2 * 1024 * 1024) else { return [] }
    return try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] ?? []
  }
  private func dismissInterruptedNotification(_ id: String) {
    do {
      for url in [interruptedLedger, ledger] {
        if let bytes = try readPrivate(url, limit: 2 * 1024 * 1024),
          let values = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] {
          let retained = values.map { value -> [String: Any] in
            guard value["id"] as? String == id else { return value }
            var hidden = value; hidden["notificationDismissed"] = true; return hidden
          }
          try atomic(JSONSerialization.data(withJSONObject: retained), url)
        }
      }
      let records = try interruptedRecords()
      jobNotifications?.restoreInterrupted(records)
      if let bytes = try? JSONSerialization.data(withJSONObject: records),
        let encoded = String(data: bytes, encoding: .utf8) {
        jobs.invokeMethod("interruptedJobsChanged", arguments: encoded)
      }
    } catch {
      // Notification bookkeeping never changes job execution or recovery.
    }
  }
  private func endBackground() { if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid } }
  @objc private func coverSnapshot() {
    guard cover == nil, let window = host?.view.window else { return }
    let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial)); view.frame = window.bounds; view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.isUserInteractionEnabled = true
    window.addSubview(view); cover = view
  }
  @objc private func uncoverSnapshot() {
    cover?.removeFromSuperview(); cover = nil; incomingChannel?.invokeMethod("changed", arguments: nil)
    queue.async { [weak self] in
      guard let self = self else { return }
      for library in self.presenters.keys { self.libraryChanged(library) }
    }
  }
  deinit {
    jobNotifications?.tearDown()
    NotificationCenter.default.removeObserver(self)
    for presenter in presenters.values { NSFileCoordinator.removeFilePresenter(presenter) }
    for value in leases.values { value.2.closeFile(); if value.3 { value.1.stopAccessingSecurityScopedResource() } }
    for url in roots.values { url.stopAccessingSecurityScopedResource() }
  }
}
