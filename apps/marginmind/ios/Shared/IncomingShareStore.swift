import Foundation

/// Shared by the extension and Runner. Each batch has one writer and becomes
/// visible only when its manifest is atomically published after all copies.
final class IncomingShareStore {
  struct Attachment: Codable {
    let name: String
    let stored: String
  }
  struct Batch: Codable {
    let id: String
    var files: [Attachment] = []
    var url: String?
    var title: String?
    var error: String?
  }
  enum Failure: Error { case unsupported, limit, unavailable }
  static let group = "group.io.github.mylxsw.marginmind"
  static let notification = "io.github.mylxsw.marginmind.incomingChanged"
  let root: URL

  init(root: URL) throws {
    self.root = root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var protectedRoot = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedRoot.setResourceValues(values)
    #if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: root.path)
    #endif
  }

  #if os(iOS)
  static func shared() throws -> IncomingShareStore {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
      throw Failure.unavailable
    }
    return try IncomingShareStore(root: container.appendingPathComponent("Incoming", isDirectory: true))
  }
  #endif

  static func limit(for name: String) throws -> Int {
    switch (name as NSString).pathExtension.lowercased() {
    case "pdf": return 256 * 1024 * 1024
    case "mobi", "azw", "azw3": return 500 * 1024 * 1024
    case "epub", "md", "markdown": return 64 * 1024 * 1024
    default: throw Failure.unsupported
    }
  }

  static func webURL(_ text: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s<>"\x00-\x1f]+"#, options: .caseInsensitive) else { return nil }
    let input = String(text.prefix(65536))
    for match in expression.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
      guard let range = Range(match.range, in: input) else { continue }
      var candidate = String(input[range])
      while let last = candidate.last, ".,;!?，。；！？".contains(last) { candidate.removeLast() }
      for (open, close): (Character, Character) in [("(", ")"), ("[", "]"), ("{", "}"), ("（", "）"), ("【", "】"), ("《", "》")] {
        var excess = candidate.filter { $0 == close }.count - candidate.filter { $0 == open }.count
        while excess > 0, candidate.last == close { candidate.removeLast(); excess -= 1 }
      }
      guard !candidate.contains("\\"), let parts = URLComponents(string: candidate),
        ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
        let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
        host.contains(".") || host == "localhost" || host.contains(":"),
        !host.hasPrefix("."), !host.contains(".."),
        parts.port == nil || (1...65535).contains(parts.port!) else { continue }
      return candidate
    }
    return nil
  }

  func begin(title: String?) throws -> Batch {
    let id = "\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
    try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
    return Batch(id: id, title: title.map { String($0.prefix(200)) })
  }

  func append(_ source: URL, name: String, to batch: inout Batch, total: inout Int) throws {
    guard batch.files.count < 20 else { throw Failure.limit }
    let safeName = (name as NSString).lastPathComponent.replacingOccurrences(of: "\\", with: "_")
      .components(separatedBy: .controlCharacters).joined(separator: "_")
    let limit = try Self.limit(for: safeName)
    let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw Failure.unsupported }
    let stored = "\(batch.files.count).\((safeName as NSString).pathExtension.lowercased())"
    let target = directory(batch.id).appendingPathComponent(stored)
    guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw Failure.unavailable }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: target)
    defer { try? output.close() }
    var size = 0
    while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
      size += data.count
      total += data.count
      guard size <= limit, total <= 512 * 1024 * 1024 else { throw Failure.limit }
      try output.write(contentsOf: data)
    }
    guard size > 0 else { throw Failure.unsupported }
    batch.files.append(Attachment(name: String(safeName.suffix(200)), stored: stored))
  }

  func publish(_ batch: Batch) throws {
    guard !batch.files.isEmpty || batch.url != nil || batch.error != nil else { throw Failure.unsupported }
    let data = try JSONEncoder().encode(batch)
    try data.write(to: directory(batch.id).appendingPathComponent("manifest.json"), options: .atomic)
    #if os(iOS)
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(Self.notification as CFString), nil, nil, true)
    #endif
  }

  func fail(_ batch: Batch, error: Error) throws {
    let folder = directory(batch.id)
    if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: directory(batch.id), withIntermediateDirectories: true)
    var failed = Batch(id: batch.id)
    failed.error = error as? Failure == .limit ? "limit" : error as? Failure == .unsupported ? "unsupported" : "unavailable"
    try publish(failed)
  }

  func pending() throws -> [[String: Any]] {
    try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { folder in
        let manifest = folder.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("completed").path) { return nil }
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        do {
          let batch = try JSONDecoder().decode(Batch.self, from: Data(contentsOf: manifest))
          guard batch.id == folder.lastPathComponent else { throw Failure.unsupported }
          let files = try batch.files.map { file -> [String: String] in
            guard file.stored == (file.stored as NSString).lastPathComponent, !file.stored.contains("\\"),
              ![".", ".."].contains(file.stored) else { throw Failure.unsupported }
            return ["name": file.name, "path": folder.appendingPathComponent(file.stored).path]
          }
          var map: [String: Any] = ["id": batch.id, "files": files]
          map["url"] = batch.url
          map["title"] = batch.title
          map["error"] = batch.error
          return map
        } catch { return ["id": folder.lastPathComponent, "error": "unavailable"] }
      }
  }

  func complete(_ id: String) throws {
    guard !id.isEmpty, id.count <= 80, id.range(of: #"^[a-zA-Z0-9-]+$"#, options: .regularExpression) != nil else {
      throw Failure.unsupported
    }
    let folder = directory(id)
    if FileManager.default.fileExists(atPath: folder.path) {
      // Persist acknowledgement before reclaiming files; a cleanup failure
      // must not offer an already-imported batch again on the next launch.
      try Data().write(to: folder.appendingPathComponent("completed"), options: .atomic)
      try? FileManager.default.removeItem(at: folder)
    }
  }

  func prune(now: Date = Date()) throws {
    for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
      if let date = try folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        now.timeIntervalSince(date) > 86400 { try FileManager.default.removeItem(at: folder) }
    }
  }

  private func directory(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
}
