import UIKit
import Foundation
import MobileCoreServices

/// Receipt only. The containing app remains the sole note/library writer.
final class ShareViewController: UIViewController {
  private let status = UILabel()
  private let bar = UIProgressView(progressViewStyle: .default)
  private let button = UIButton(type: .system)
  private let cancellation = Progress(totalUnitCount: 1)
  private var batch: URL?
  private var ready = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    status.text = "Preparing shared files…"
    status.numberOfLines = 0
    button.setTitle("Cancel", for: .normal)
    button.addTarget(self, action: #selector(finish), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [status, bar, button])
    stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor), button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
    ])
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.receive(providers) }
  }

  @objc private func finish() {
    cancellation.cancel()
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func receive(_ providers: [NSItemProvider]) {
    let fm = FileManager.default
    do {
      guard (1...128).contains(providers.count),
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nativedevps.futurenotes") else {
        throw NSError(domain: "ShareInbox", code: 1)
      }
      let root = container.appendingPathComponent("IncomingShares", isDirectory: true)
      try fm.createDirectory(at: root, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      var excluded = root; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try excluded.setResourceValues(flags)
      let id = UUID().uuidString
      let folder = root.appendingPathComponent(id, isDirectory: true)
      try fm.createDirectory(at: folder, withIntermediateDirectories: false,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      batch = folder
      var records: [[String: Any]] = []
      for (index, provider) in providers.enumerated() {
        if cancellation.isCancelled { throw NSError(domain: "ShareInbox", code: 2) }
        guard let type = provider.registeredTypeIdentifiers.first(where: {
          UTTypeConformsTo($0 as CFString, kUTTypeData) || UTTypeConformsTo($0 as CFString, kUTTypeFileURL)
        }) else { throw NSError(domain: "ShareInbox", code: 3) }
        let done = DispatchSemaphore(value: 0)
        var copied: [String: Any]?
        var copyError: Error?
        let load = provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
          defer { done.signal() }
          guard let self = self, let url = url, error == nil else { copyError = error ?? NSError(domain: "ShareInbox", code: 4); return }
          do {
            let destination = folder.appendingPathComponent("file-\(index).bin")
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
              do {
                let input = try FileHandle(forReadingFrom: source)
                defer { input.closeFile() }
                guard fm.createFile(atPath: destination.path, contents: nil,
                  attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw NSError(domain: "ShareInbox", code: 5) }
                let output = try FileHandle(forWritingTo: destination)
                defer { output.closeFile() }
                let total = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                var bytes: Int64 = 0
                while true {
                  if self.cancellation.isCancelled { throw NSError(domain: "ShareInbox", code: 2) }
                  let chunk = input.readData(ofLength: 1024 * 1024)
                  if chunk.isEmpty { break }
                  bytes += Int64(chunk.count)
                  guard bytes <= 10 * 1024 * 1024 * 1024 else { throw NSError(domain: "ShareInbox", code: 6) }
                  try output.write(contentsOf: chunk)
                  let current = bytes
                  DispatchQueue.main.async {
                    self.status.text = "Receiving file \(index + 1) of \(providers.count)\n\(provider.suggestedName ?? source.lastPathComponent)\n\(ByteCountFormatter.string(fromByteCount: current, countStyle: .file))"
                    self.bar.progress = total > 0 ? Float(current) / Float(total) : 0
                  }
                }
                try output.synchronize()
                if total > 0 && bytes != Int64(total) { throw NSError(domain: "ShareInbox", code: 7) }
                copied = ["name": provider.suggestedName ?? source.lastPathComponent, "file": destination.lastPathComponent, "length": bytes]
              } catch { copyError = error }
            }
            if let error = coordinationError { throw error }
          } catch { copyError = error }
        }
        if done.wait(timeout: .now() + 120) != .success { load.cancel(); cancellation.cancel(); throw NSError(domain: "ShareInbox", code: 8) }
        if let error = copyError { throw error }
        guard let record = copied else { throw NSError(domain: "ShareInbox", code: 9) }
        records.append(record)
      }
      if cancellation.isCancelled { throw NSError(domain: "ShareInbox", code: 2) }
      let receipt = try JSONSerialization.data(withJSONObject: ["version": 1, "id": id, "sources": records])
      try receipt.write(to: folder.appendingPathComponent("receipt.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      DispatchQueue.main.async {
        self.ready = true
        self.status.text = "Files ready\nOpen Future Notes to choose a note."
        self.bar.progress = 1
        self.button.setTitle("Done", for: .normal)
      }
    } catch {
      if let batch = batch { try? fm.removeItem(at: batch) }
      DispatchQueue.main.async {
        self.status.text = "These files could not be received. Keep the original files and share them again."
        self.button.setTitle("Close", for: .normal)
      }
    }
  }
}
