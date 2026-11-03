import Foundation

@main struct IncomingShareStoreTests {
  static func check(_ condition: Bool, _ message: String = "Assertion failed") { precondition(condition, message) }

  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try IncomingShareStore(root: root.appendingPathComponent("inbox"))
    let source = root.appendingPathComponent("book.epub")
    try Data("book fixture".utf8).write(to: source)
    var batch = try store.begin(title: "Book")
    var size = 0
    try store.append(source, name: "../../book.epub", to: &batch, total: &size)
    check(try store.pending().isEmpty, "Incomplete copies must not be visible")
    try store.publish(batch)
    let loaded = try store.pending()
    check(loaded.count == 1)
    let file = (loaded[0]["files"] as! [[String: String]])[0]
    check(file["name"] == "book.epub")
    check(try Data(contentsOf: URL(fileURLWithPath: file["path"]!)) == Data("book fixture".utf8))
    check(try store.pending().count == 1, "Reads do not consume a batch")
    try store.complete(batch.id)
    try store.complete(batch.id)
    check(try store.pending().isEmpty)

    do { try store.complete("../outside"); fatalError("Traversal accepted") }
    catch IncomingShareStore.Failure.unsupported {}
    for name in ["test.exe", "test", "."] {
      do { _ = try IncomingShareStore.limit(for: name); fatalError("Unsupported type accepted") }
      catch IncomingShareStore.Failure.unsupported {}
    }
    check(try IncomingShareStore.limit(for: "a.PDF") == 256 * 1024 * 1024)
    check(try IncomingShareStore.limit(for: "a.azw3") == 500 * 1024 * 1024)
    check(IncomingShareStore.webURL("标题 https://example.com/article。") == "https://example.com/article")
    check(IncomingShareStore.webURL("javascript:alert(1)") == nil)
    check(IncomingShareStore.webURL("https://example.com/Foo_(bar)") == "https://example.com/Foo_(bar)")
    check(IncomingShareStore.webURL("https://u:p@example.com") == nil)
    check(IncomingShareStore.webURL("https://bad") == nil)
    check(IncomingShareStore.webURL("https://example.com:99999") == nil)
    check(IncomingShareStore.webURL("https://u:p@example.com HTTPS://good.example/a") == "HTTPS://good.example/a")

    var failed = try store.begin(title: nil)
    var oversized = 512 * 1024 * 1024
    do { try store.append(source, name: "book.epub", to: &failed, total: &oversized); fatalError("Budget exceeded") }
    catch IncomingShareStore.Failure.limit {}
    try store.fail(failed, error: IncomingShareStore.Failure.limit)
    check(try store.pending().first?["error"] as? String == "limit")
    check(try store.pending().first?["files"] as? [[String: String]] == [])
    try store.prune(now: Date().addingTimeInterval(86401))
    check(try store.pending().isEmpty)

    var empty = try store.begin(title: nil)
    do { try store.publish(empty); fatalError("Empty batch published") }
    catch IncomingShareStore.Failure.unsupported {}
    empty.url = "https://example.com"
    try store.publish(empty)
    check(try store.pending().first?["url"] as? String == "https://example.com")
    print("IncomingShareStore: copy, atomic publication, replay, cleanup, URL and size policy passed")
  }
}
