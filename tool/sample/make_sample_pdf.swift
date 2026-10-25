// Renders tool/sample/sample.txt into the bundled sample PDF with a real
// text layer, so text selection and highlighting work on it.
//
//   swift tool/sample/make_sample_pdf.swift tool/sample/sample.txt \
//     apps/marginmind/assets/sample/sample.pdf
//
// Format: line 1 = title, line 2 = subtitle, "## " = section heading,
// blank lines separate paragraphs. macOS only (CoreText).
import AppKit
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
  fputs("usage: make_sample_pdf.swift <input.txt> <output.pdf>\n", stderr)
  exit(2)
}
let lines = try String(contentsOfFile: args[1], encoding: .utf8).components(separatedBy: "\n")

func font(_ name: String, _ size: CGFloat) -> NSFont {
  NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
}

func paragraph(indent: CGFloat, before: CGFloat, after: CGFloat, lineSpacing: CGFloat) -> NSParagraphStyle {
  let p = NSMutableParagraphStyle()
  p.firstLineHeadIndent = indent
  p.paragraphSpacingBefore = before
  p.paragraphSpacing = after
  p.lineSpacing = lineSpacing
  return p
}

let text = NSMutableAttributedString()
func append(_ s: String, _ f: NSFont, _ p: NSParagraphStyle, gray: CGFloat = 0.1) {
  text.append(NSAttributedString(string: s + "\n", attributes: [
    .font: f,
    .paragraphStyle: p,
    .foregroundColor: NSColor(white: gray, alpha: 1),
  ]))
}

append(lines[0], font("STSongti-SC-Bold", 22), paragraph(indent: 0, before: 0, after: 6, lineSpacing: 4))
append(lines[1], font("PingFangSC-Regular", 9.5), paragraph(indent: 0, before: 0, after: 18, lineSpacing: 0), gray: 0.45)
for line in lines.dropFirst(2) {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  if trimmed.isEmpty { continue }
  if trimmed.hasPrefix("## ") {
    append(String(trimmed.dropFirst(3)), font("STSongti-SC-Bold", 14.5), paragraph(indent: 0, before: 14, after: 8, lineSpacing: 4))
  } else {
    append(trimmed, font("STSongti-SC-Regular", 12.5), paragraph(indent: 25, before: 0, after: 9, lineSpacing: 9))
  }
}

var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
guard let ctx = CGContext(URL(fileURLWithPath: args[2]) as CFURL, mediaBox: &mediaBox, [
  kCGPDFContextTitle: "MarginMind 示例章节",
  kCGPDFContextCreator: "MarginMind",
] as CFDictionary) else { fatalError("cannot create PDF") }

let setter = CTFramesetterCreateWithAttributedString(text)
var start = 0
var pageNumber = 1
while start < text.length {
  ctx.beginPDFPage(nil)
  let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0),
                                       CGPath(rect: mediaBox.insetBy(dx: 72, dy: 80), transform: nil), nil)
  CTFrameDraw(frame, ctx)
  let footer = CTLineCreateWithAttributedString(NSAttributedString(string: "\(pageNumber)", attributes: [
    .font: font("PingFangSC-Regular", 9),
    .foregroundColor: NSColor(white: 0.5, alpha: 1),
  ]))
  ctx.textPosition = CGPoint(x: 295, y: 44)
  CTLineDraw(footer, ctx)
  ctx.endPDFPage()
  start += CTFrameGetVisibleStringRange(frame).length
  pageNumber += 1
}
ctx.closePDF()
print("wrote \(pageNumber - 1) pages to \(args[2])")
