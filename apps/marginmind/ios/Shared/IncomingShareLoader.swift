import Foundation
import UniformTypeIdentifiers

/// NSItemProvider's temporary URL must be copied *inside* its completion block.
/// Attachments are loaded sequentially to keep extension memory bounded.
enum IncomingShareLoader {
  static func receive(_ providers: [NSItemProvider], title: String?, store: IncomingShareStore) async throws {
    var batch = try store.begin(title: title)
    var total = 0
    do {
      guard !providers.isEmpty else { throw IncomingShareStore.Failure.unsupported }
      guard providers.count <= 20 else { throw IncomingShareStore.Failure.limit }
      for provider in providers {
        let fileType = provider.registeredTypeIdentifiers.first { identifier in
          guard let type = UTType(identifier) else { return false }
          let namedDocument = provider.suggestedName.map { (try? IncomingShareStore.limit(for: $0)) != nil } ?? false
          return type.conforms(to: .pdf) || type.conforms(to: .epub) ||
            type.conforms(to: .fileURL) ||
            (namedDocument && type.conforms(to: .data) && !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)) ||
            ["mobi", "azw", "azw3", "md", "markdown"].contains(type.preferredFilenameExtension ?? "")
        }
        if let type = fileType {
          // Mutate only after the provider's callback completed; no inout value
          // escapes into a concurrently running closure.
          let current = batch
          let currentTotal = total
          let copied: (IncomingShareStore.Batch, Int) = try await withCheckedThrowingContinuation { continuation in
            let copy: (URL) -> Void = { url in
              do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                var next = current
                var size = currentTotal
                if !url.isFileURL {
                  guard let web = IncomingShareStore.webURL(url.absoluteString) else { throw IncomingShareStore.Failure.unsupported }
                  next.url = next.url ?? web
                  continuation.resume(returning: (next, size))
                  return
                }
                let name = provider.suggestedName.flatMap { suggested -> String? in
                  if (suggested as NSString).pathExtension.isEmpty {
                    guard type != UTType.fileURL.identifier,
                      let ext = UTType(type)?.preferredFilenameExtension else { return nil }
                    return suggested + "." + ext
                  }
                  return suggested
                } ?? url.lastPathComponent
                try store.append(url, name: name, to: &next, total: &size)
                continuation.resume(returning: (next, size))
              } catch { continuation.resume(throwing: error) }
            }
            if type == UTType.fileURL.identifier {
              if provider.canLoadObject(ofClass: NSURL.self) {
                provider.loadObject(ofClass: NSURL.self) { value, error in
                  if let url = value as? NSURL { copy(url as URL) }
                  else { continuation.resume(throwing: error ?? IncomingShareStore.Failure.unsupported) }
                }
              } else {
                provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                  if let url = value as? URL { copy(url) }
                  else if let data = value as? Data, let text = String(data: data, encoding: .utf8),
                    let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.isFileURL { copy(url) }
                  else if let text = value as? String, let url = URL(string: text), url.isFileURL { copy(url) }
                  else { continuation.resume(throwing: error ?? IncomingShareStore.Failure.unsupported) }
                }
              }
            } else {
              provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let url = url { copy(url) }
                else { continuation.resume(throwing: error ?? IncomingShareStore.Failure.unavailable) }
              }
            }
          }
          batch = copied.0
          total = copied.1
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          let raw = try await item(provider, type: UTType.url.identifier)
          if let url = IncomingShareStore.webURL(raw) { batch.url = batch.url ?? url }
          else { throw IncomingShareStore.Failure.unsupported }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          let raw = try await item(provider, type: UTType.plainText.identifier)
          if let url = IncomingShareStore.webURL(raw) { batch.url = batch.url ?? url }
          // A file share may also include its title as a plain-text attachment.
        } else { throw IncomingShareStore.Failure.unsupported }
      }
      if !batch.files.isEmpty { batch.url = nil }
      try store.publish(batch)
    } catch {
      try store.fail(batch, error: error)
      throw error
    }
  }

  private static func item(_ provider: NSItemProvider, type: String) async throws -> String {
    // Typed readers preserve the provider's URL/text representation. loadItem
    // can return an opaque NSData even for an NSString/NSURL writer on iOS.
    if type == UTType.url.identifier && provider.canLoadObject(ofClass: NSURL.self) {
      return try await withCheckedThrowingContinuation { continuation in
        provider.loadObject(ofClass: NSURL.self) { value, error in
          if let url = value as? NSURL { continuation.resume(returning: (url as URL).absoluteString) }
          else { continuation.resume(throwing: error ?? IncomingShareStore.Failure.unsupported) }
        }
      }
    }
    if provider.canLoadObject(ofClass: NSString.self) {
      return try await withCheckedThrowingContinuation { continuation in
        provider.loadObject(ofClass: NSString.self) { value, error in
          if let text = value as? NSString { continuation.resume(returning: text as String) }
          else { continuation.resume(throwing: error ?? IncomingShareStore.Failure.unsupported) }
        }
      }
    }
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
        if let url = value as? URL { continuation.resume(returning: url.absoluteString) }
        else if let text = value as? String { continuation.resume(returning: text) }
        else if let data = value as? Data, let text = String(data: data, encoding: .utf8) {
          continuation.resume(returning: text)
        }
        else { continuation.resume(throwing: error ?? IncomingShareStore.Failure.unsupported) }
      }
    }
  }
}
