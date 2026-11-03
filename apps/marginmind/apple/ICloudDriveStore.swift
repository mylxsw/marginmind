import Foundation
import Darwin

enum ICloudDriveFailure: String, Error {
  case unavailable, accountChanged, invalidResponse, tooLarge, collision
}

/// A local alias for Apple's opaque token. Never hash its archive into a global
/// user ID: Apple's contract is isEqual, not stable serialized bytes.
final class ICloudAccountRegistry {
  private let defaults: UserDefaults
  private let key = "foliarc.icloud.accounts.v1"
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func identity(_ token: (NSCoding & NSCopying & NSObjectProtocol)?) throws -> String? {
    guard let token = token else { return nil }
    var records: [[String: Any]] = []
    if let saved = defaults.object(forKey: key) {
      guard let values = saved as? [[String: Any]] else { throw ICloudDriveFailure.unavailable }
      records = values
    }
    for record in records {
      guard let data = record["token"] as? Data, let id = record["id"] as? String, UUID(uuidString: id) != nil else {
        throw ICloudDriveFailure.unavailable
      }
      // The system's opaque identity promises NSCoding, not NSSecureCoding.
      let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
      decoder.requiresSecureCoding = false
      decoder.decodingFailurePolicy = .setErrorAndReturn
      defer { decoder.finishDecoding() }
      guard let previous = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject else {
        throw ICloudDriveFailure.unavailable
      }
      if token.isEqual(previous) { return id }
    }
    let id = UUID().uuidString
    let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    records.append(["token": data, "id": id])
    defaults.set(records, forKey: key)
    return id
  }
}

/// All calls run on the channel's serial worker, never on the Flutter/UI thread.
/// The injected callbacks allow filesystem tests without an iCloud account.
final class ICloudDriveStore {
  static let byteLimit = 16 * 1024 * 1024
  let container: String
  private let files = FileManager.default
  private let root: () throws -> URL
  private let account: () throws -> String?
  private let state: (URL) throws -> (current: Bool, uploaded: Bool, conflicts: Bool)
  private let download: (URL) throws -> Void

  init(container: String, root: @escaping () throws -> URL,
       account: @escaping () throws -> String?,
       state: @escaping (URL) throws -> (current: Bool, uploaded: Bool, conflicts: Bool),
       download: @escaping (URL) throws -> Void) {
    self.container = container; self.root = root; self.account = account
    self.state = state; self.download = download
  }

  static func configuredContainer(_ bundle: Bundle = .main) -> String? {
    guard let value = bundle.object(forInfoDictionaryKey: "FoliarcICloudContainerIdentifier") as? String,
          value.range(of: #"\AiCloud\.[A-Za-z0-9.-]{1,200}\z"#, options: .regularExpression) != nil else { return nil }
    return value
  }

  static func production(container: String) -> ICloudDriveStore {
    let files = FileManager.default, registry = ICloudAccountRegistry()
    return ICloudDriveStore(container: container, root: {
      guard let url = files.url(forUbiquityContainerIdentifier: container) else {
        throw ICloudDriveFailure.unavailable
      }
      return url.appendingPathComponent("Documents", isDirectory: true)
    }, account: { try registry.identity(files.ubiquityIdentityToken) }, state: fileState,
       download: { try files.startDownloadingUbiquitousItem(at: $0) })
  }

  static func fileState(_ url: URL) throws -> (current: Bool, uploaded: Bool, conflicts: Bool) {
    let values = try url.resourceValues(forKeys: [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
        .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey,
        .ubiquitousItemHasUnresolvedConflictsKey
      ])
    let conflicts = values.ubiquitousItemHasUnresolvedConflicts == true ||
        !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
    return (
        values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .current &&
          values.ubiquitousItemDownloadingError == nil,
        values.isUbiquitousItem == true && values.ubiquitousItemIsUploaded == true &&
          values.ubiquitousItemIsUploading != true && values.ubiquitousItemUploadingError == nil,
        conflicts
    )
  }

  func accountIdentity() throws -> String? { try account() }

  private func check(_ expected: String) throws {
    guard !expected.isEmpty, expected.count <= 256, try account() == expected else {
      throw ICloudDriveFailure.accountChanged
    }
  }

  static func valid(_ path: String, directory: Bool) -> Bool {
    let suffix = directory ? "(commits|blobs)" : #"(library\.json|commits/[a-f0-9]{64}\.json|blobs/[a-f0-9]{64}\.bin)"#
    return path.range(of: "\\Afoliarc-v2/[a-f0-9]{64}/" + suffix + "\\z", options: .regularExpression) != nil
  }

  /// Reject symlinks before and inside coordination, including existing parent
  /// components. No user-supplied absolute paths or resource paths are accepted.
  private func safe(_ url: URL, root: URL) throws {
    guard url.standardizedFileURL.path == root.standardizedFileURL.path ||
      url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
      throw ICloudDriveFailure.invalidResponse
    }
    var current = url
    while true {
      if let attributes = try? files.attributesOfItem(atPath: current.path),
         attributes[.type] as? FileAttributeType == .typeSymbolicLink {
        throw ICloudDriveFailure.invalidResponse
      }
      if current.path == root.path { break }
      let parent = current.deletingLastPathComponent()
      guard parent.path != current.path else { throw ICloudDriveFailure.invalidResponse }
      current = parent
    }
  }

  private func access<T>(_ path: String, expected: String, directory: Bool = false,
                         writing: Bool = false, _ body: (URL) throws -> T) throws -> T {
    guard Self.valid(path, directory: directory) else { throw ICloudDriveFailure.invalidResponse }
    try check(expected)
    let base = try root().standardizedFileURL
    try check(expected) // Resolving the container can block across account changes.
    let url = base.appendingPathComponent(path)
    try safe(url, root: base)
    var result: Result<T, Error>?
    var coordination: NSError?
    let accessor: (URL) -> Void = { coordinated in
      result = Result {
        try self.check(expected)
        guard coordinated.standardizedFileURL == url.standardizedFileURL else {
          throw ICloudDriveFailure.invalidResponse
        }
        try self.safe(coordinated, root: base)
        let value = try body(coordinated)
        try self.check(expected)
        return value
      }
    }
    let coordinator = NSFileCoordinator(filePresenter: nil)
    if writing {
      coordinator.coordinate(writingItemAt: url, options: [], error: &coordination, byAccessor: accessor)
    } else {
      coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordination, byAccessor: accessor)
    }
    if let error = coordination { throw error }
    guard let result = result else { throw ICloudDriveFailure.unavailable }
    return try result.get()
  }

  func prepare(_ path: String, expected: String) throws {
    try access(path, expected: expected, directory: true, writing: true) { url in
      try files.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  func list(_ path: String, expected: String) throws -> [String] {
    try access(path, expected: expected, directory: true) { url in
      let children = try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
      guard children.count <= 100000 else { throw ICloudDriveFailure.tooLarge }
      var names = Set<String>()
      for child in children {
        var name = child.lastPathComponent
        // Evicted iCloud documents may be represented by hidden placeholders.
        if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(7)) }
        if name.range(of: #"\A[a-f0-9]{64}\.json\z"#, options: .regularExpression) != nil { names.insert(name) }
      }
      return names.sorted()
    }
  }

  private func placeholder(_ url: URL) -> URL {
    url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
  }

  private func currentData(_ url: URL) throws -> Data? {
    guard files.fileExists(atPath: url.path) else {
      if files.fileExists(atPath: placeholder(url).path) {
        try download(url)
        throw ICloudDriveFailure.unavailable
      }
      return nil
    }
    let attributes = try files.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ICloudDriveFailure.invalidResponse }
    guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.byteLimit else {
      throw ICloudDriveFailure.tooLarge
    }
    let status = try state(url)
    guard !status.conflicts else { throw ICloudDriveFailure.collision }
    guard status.current else { try download(url); throw ICloudDriveFailure.unavailable }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: Self.byteLimit + 1) ?? Data()
    guard data.count <= Self.byteLimit else { throw ICloudDriveFailure.tooLarge }
    return data
  }

  func read(_ path: String, expected: String) throws -> Data? {
    try access(path, expected: expected) { try currentData($0) }
  }

  func create(_ path: String, bytes: Data, expected: String) throws {
    guard bytes.count <= Self.byteLimit else { throw ICloudDriveFailure.tooLarge }
    try access(path, expected: expected, writing: true) { url in
      // Existing/evicted versions are never overwritten. Dart reads back and
      // compares canonical JSON, including VM/JS numeric representations.
      if try currentData(url) != nil { return }
      let temporary = url.deletingLastPathComponent().appendingPathComponent(".sync-" + UUID().uuidString)
      try bytes.write(to: temporary, options: .withoutOverwriting)
      defer { try? files.removeItem(at: temporary) }
      let handle = try FileHandle(forWritingTo: temporary)
      defer { try? handle.close() }
      try handle.synchronize()
      try check(expected)
      // .atomic + .withoutOverwriting is not a supported NSData combination.
      // Same-directory rename with EXCL publishes complete bytes or nothing.
      let code = temporary.path.withCString { source in
        url.path.withCString { destination in renamex_np(source, destination, UInt32(RENAME_EXCL)) }
      }
      if code != 0 && errno != EEXIST { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
  }

  func uploaded(_ path: String, bytes: Data, expected: String) throws -> Bool {
    guard bytes.count <= Self.byteLimit else { throw ICloudDriveFailure.tooLarge }
    return try access(path, expected: expected) { url in
      guard let stored = try currentData(url), stored == bytes else { return false }
      let status = try state(url)
      return status.current && status.uploaded && !status.conflicts
    }
  }
}
