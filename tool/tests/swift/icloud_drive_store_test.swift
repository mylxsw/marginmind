import Foundation

@main
struct ICloudDriveStoreTest {
  static func main() throws {
    func verify(_ condition: @autoclosure () throws -> Bool, _ message: String = "") throws {
      let value = try condition(); precondition(value, message)
    }
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("foliarc-drive-test-" + UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    let base = "foliarc-v2/" + String(repeating: "a", count: 64)
    let directory = base + "/commits", path = base + "/library.json"
    let id = String(repeating: "b", count: 64)
    var account: String? = "first", isCurrent = true, isUploaded = false, conflicts = false
    var downloads = 0, accesses = 0, switchOnAccess = false
    let store = ICloudDriveStore(container: "iCloud.test", root: { root }, account: {
      accesses += 1
      if switchOnAccess && accesses == 3 { account = "second" }
      return account
    }, state: { _ in (isCurrent, isUploaded, conflicts) }, download: { _ in downloads += 1 })
    func fails(_ kind: ICloudDriveFailure, _ body: () throws -> Void) {
      do { try body(); fatalError("Expected \(kind)") }
      catch { precondition(error as? ICloudDriveFailure == kind, "Unexpected \(error)") }
    }
    try verify(try store.accountIdentity() == "first")
    for invalid in ["", "/tmp/file", "../library.json", path + "/x", path + "\n", base + "/commits/../library.json"] {
      fails(.invalidResponse) { _ = try store.read(invalid, expected: "first") }
    }
    fails(.invalidResponse) { try store.prepare(path, expected: "first") }
    fails(.accountChanged) { try store.prepare(directory, expected: "old") }
    fails(.accountChanged) { try store.prepare(directory, expected: "") }
    // Settings probes a new library without preparing/writing its directory.
    try verify(try store.read(path, expected: "first") == nil)
    try store.prepare(directory, expected: "first")
    try verify(try store.read(path, expected: "first") == nil)
    try verify(try store.uploaded(path, bytes: Data(), expected: "first") == false)
    let blob = base + "/blobs/" + id + ".bin"
    try store.prepare(base + "/blobs", expected: "first")
    let binary = Data([0, 255, 128, 1])
    try store.create(blob, bytes: binary, expected: "first")
    try verify(try store.read(blob, expected: "first") == binary)
    try verify(try store.uploaded(blob, bytes: binary, expected: "first") == false)
    fails(.invalidResponse) { _ = try store.read(base + "/blobs/../library.json", expected: "first") }
    fails(.invalidResponse) { _ = try store.read(base + "/blobs/" + id + ".json", expected: "first") }
    let bytes = Data("{}".utf8)
    try store.create(path, bytes: bytes, expected: "first")
    let localState = try ICloudDriveStore.fileState(root.appendingPathComponent(path))
    try verify(!localState.current && !localState.uploaded && !localState.conflicts,
               "Ordinary local file must never confirm cloud delivery")
    try store.create(path, bytes: Data("different".utf8), expected: "first")
    try verify(try store.read(path, expected: "first") == bytes, "Never overwrite immutable object")
    try verify(try store.uploaded(path, bytes: bytes, expected: "first") == false)
    isUploaded = true
    try verify(try store.uploaded(path, bytes: bytes, expected: "first"))
    try verify(try store.uploaded(path, bytes: Data(), expected: "first") == false)
    conflicts = true
    fails(.collision) { _ = try store.uploaded(path, bytes: bytes, expected: "first") }
    conflicts = false; isCurrent = false
    fails(.unavailable) { _ = try store.read(path, expected: "first") }
    try verify(downloads == 1)
    isCurrent = true
    let placeholder = root.appendingPathComponent(directory + "/." + id + ".json.icloud")
    try Data().write(to: placeholder)
    try verify(try store.list(directory, expected: "first") == [id + ".json"])
    fails(.unavailable) { try store.create(directory + "/" + id + ".json", bytes: bytes, expected: "first") }
    try verify(downloads == 2)
    try files.removeItem(at: placeholder)
    try store.create(directory + "/" + id + ".json", bytes: bytes, expected: "first")
    try verify(try store.list(directory, expected: "first") == [id + ".json"])
    let oversized = Data(repeating: 0, count: ICloudDriveStore.byteLimit + 1)
    fails(.tooLarge) { try store.create(path, bytes: oversized, expected: "first") }
    fails(.tooLarge) { _ = try store.uploaded(path, bytes: oversized, expected: "first") }
    try oversized.write(to: root.appendingPathComponent(path))
    fails(.tooLarge) { _ = try store.read(path, expected: "first") }
    try files.removeItem(at: root.appendingPathComponent(path))
    try files.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: false)
    fails(.invalidResponse) { _ = try store.read(path, expected: "first") }
    try files.removeItem(at: root.appendingPathComponent(path))
    try files.createSymbolicLink(at: root.appendingPathComponent(path), withDestinationURL: root)
    fails(.invalidResponse) { _ = try store.read(path, expected: "first") }
    try files.removeItem(at: root.appendingPathComponent(path))
    // Account switch after root resolution, before the coordinated body.
    accesses = 0; switchOnAccess = true
    fails(.accountChanged) { try store.create(path, bytes: bytes, expected: "first") }
    try verify(!files.fileExists(atPath: root.appendingPathComponent(path).path))
    switchOnAccess = false; account = nil
    try verify(try store.accountIdentity() == nil)
    fails(.accountChanged) { _ = try store.read(path, expected: "first") }
    // Compare archived tokens using isEqual; sign-out and return reuse identity.
    let suite = "foliarc-drive-test-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let registry = ICloudAccountRegistry(defaults: defaults)
    let first = try registry.identity("first" as NSString)
    try verify(first != nil)
    try verify(try registry.identity(nil) == nil)
    try verify(try registry.identity("second" as NSString) != first)
    try verify(try ICloudAccountRegistry(defaults: defaults).identity("first" as NSString) == first)
    defaults.set([["id": "broken"]], forKey: "foliarc.icloud.accounts.v1")
    fails(.unavailable) { _ = try registry.identity("first" as NSString) }
    defaults.set("damaged", forKey: "foliarc.icloud.accounts.v1")
    fails(.unavailable) { _ = try registry.identity("first" as NSString) }
    try verify(ICloudDriveStore.configuredContainer() == nil)
    for configured in ["iCloud.test", "iCloud.test\n", "$(FOLIARC_ICLOUD_CONTAINER_IDENTIFIER)", ""] {
      let bundleURL = root.appendingPathComponent(UUID().uuidString + ".bundle")
      try files.createDirectory(at: bundleURL, withIntermediateDirectories: true)
      let info = try PropertyListSerialization.data(fromPropertyList: [
        "CFBundleIdentifier": "io.foliarc.test", "CFBundleVersion": "1",
        "FoliarcICloudContainerIdentifier": configured
      ], format: .xml, options: 0)
      try info.write(to: bundleURL.appendingPathComponent("Info.plist"))
      let bundle = Bundle(url: bundleURL)!
      try verify(ICloudDriveStore.configuredContainer(bundle) == (configured == "iCloud.test" ? configured : nil))
    }
    print("iCloud native store tests passed")
  }
}
