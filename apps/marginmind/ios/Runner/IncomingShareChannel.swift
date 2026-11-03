import Flutter
import UIKit
import UniformTypeIdentifiers

final class IncomingShareChannel {
  private static let worker = DispatchQueue(label: "io.github.mylxsw.marginmind.incoming")
  private static weak var current: IncomingShareChannel?
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "marginmind/incoming_share", binaryMessenger: messenger)
    Self.current = self
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(), { _, _, _, _, _ in IncomingShareChannel.changed() },
      IncomingShareStore.notification as CFString, nil, .deliverImmediately)
    Self.worker.async { try? IncomingShareStore.shared().prune() }
    channel.setMethodCallHandler { call, result in
      guard ["pending", "complete"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
      Self.worker.async {
        do {
          let store = try IncomingShareStore.shared()
          if call.method == "pending" {
            let batches = try store.pending()
            DispatchQueue.main.async { result(batches) }
          } else {
            guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
              throw IncomingShareStore.Failure.unsupported
            }
            try store.complete(id)
            DispatchQueue.main.async { result(nil) }
          }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "incoming_unavailable", message: nil, details: nil)) }
        }
      }
    }
  }

  deinit {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(IncomingShareStore.notification as CFString), nil)
  }

  static func changed() {
    DispatchQueue.main.async { current?.channel.invokeMethod("changed", arguments: nil) }
  }

  static func receive(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let access = urls.map { $0.startAccessingSecurityScopedResource() }
    worker.async {
      defer {
        for (url, allowed) in zip(urls, access) where allowed { url.stopAccessingSecurityScopedResource() }
        changed()
      }
      do {
        let store = try IncomingShareStore.shared()
        var batch = try store.begin(title: nil)
        var total = 0
        do {
          guard urls.count <= 20 else { throw IncomingShareStore.Failure.limit }
          for url in urls {
            if url.isFileURL {
              var failure: Error?
              var coordination: NSError?
              NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordination) { source in
                do { try store.append(source, name: url.lastPathComponent, to: &batch, total: &total) }
                catch { failure = error }
              }
              if let error = coordination { throw error }
              if let error = failure { throw error }
            } else if let web = IncomingShareStore.webURL(url.absoluteString) {
              batch.url = batch.url ?? web
            } else { throw IncomingShareStore.Failure.unsupported }
          }
          if !batch.files.isEmpty { batch.url = nil }
          try store.publish(batch)
        } catch { try store.fail(batch, error: error) }
      } catch { /* A missing App Group is reported by the inbox channel. */ }
    }
  }
}

/// One interaction on the Flutter view accepts external iPad Split View drops.
/// The same target picker keeps the user's destination choice explicit.
final class IncomingShareDrop: NSObject, UIDropInteractionDelegate {
  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    session.localDragSession == nil && session.hasItemsConforming(toTypeIdentifiers: [
      UTType.fileURL.identifier, UTType.url.identifier, UTType.pdf.identifier,
      UTType.epub.identifier
    ])
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
    UIDropProposal(operation: .copy)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    let providers = session.items.map { $0.itemProvider }
    Task.detached {
      do { try await IncomingShareLoader.receive(providers, title: nil, store: IncomingShareStore.shared()) }
      catch { /* The loader persists the localized failure code for the app. */ }
      IncomingShareChannel.changed()
    }
  }
}
