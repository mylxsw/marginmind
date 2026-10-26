import PDFKit
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let chapRe = try! NSRegularExpression(pattern: "^第 \\d+ 章")
let secRe = try! NSRegularExpression(pattern: "^\\d+\\.\\d+ \\S")
var out: [[Any]] = []
for i in 0..<doc.pageCount {
  for raw in (doc.page(at: i)!.string ?? "").components(separatedBy: "\n").prefix(8) {
    let line = raw.trimmingCharacters(in: .whitespaces)
    let r = NSRange(line.startIndex..., in: line)
    if chapRe.firstMatch(in: line, range: r) != nil { out.append([0, line, i]) }
    else if secRe.firstMatch(in: line, range: r) != nil { out.append([1, line, i]) }
  }
}
print(String(data: try! JSONSerialization.data(withJSONObject: out), encoding: .utf8)!)
