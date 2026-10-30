import Cocoa
import PDFKit

// Compiled beside the production MapExportChannel.swift, so evidence exercises
// the exact encoder used by the app rather than a parallel implementation.
@main
struct NoteExportEvidence {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else { fatalError("Usage: note-pdf-evidence scene.json output.pdf") }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let args = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [String: Any]
    let data = try MapExportChannel.pdf(args)
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    let document = PDFDocument(data: data)!
    for index in 0..<document.pageCount {
      let page = document.page(at: index)!
      let image = page.thumbnail(of: NSSize(width: 1191, height: 1684), for: .mediaBox)
      let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
      let output = URL(fileURLWithPath: CommandLine.arguments[2]).deletingPathExtension().appendingPathExtension("page-\(index + 1).png")
      try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    }
    print("Rendered \(document.pageCount) A4 pages, \(document.string?.count ?? 0) searchable characters")
  }
}
