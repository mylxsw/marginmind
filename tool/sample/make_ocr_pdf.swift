// Deterministic image-only bilingual PDF for OCR acceptance runs.
// swift tool/sample/make_ocr_pdf.swift /absolute/output.pdf [pages]
import Cocoa
import CoreText
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let count = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 12
var media = CGRect(x: 0, y: 0, width: 600, height: 800)
let pdf = CGContext(output as CFURL, mediaBox: &media, nil)!
for page in 1...count {
  autoreleasepool {
    let bitmap = CGContext(data: nil, width: 1200, height: 1600, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
    let lines = ["学习与思考", "Learning through practice", "第 \(page) 页 · 本机文字识别", "知识来自观察，也来自实践。", "Read, select, search and connect ideas."]
    for (index, text) in lines.enumerated() {
      bitmap.textPosition = CGPoint(x: 120, y: 1380 - index * 160)
      CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes:
        [.font: NSFont(name: "PingFangSC-Regular", size: index == 0 ? 72 : 40)!])), bitmap)
    }
    pdf.beginPDFPage(nil); pdf.draw(bitmap.makeImage()!, in: media); pdf.endPDFPage()
  }
}
pdf.closePDF()
