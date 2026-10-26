// Deterministic 300-page fixture; macOS only.
// swift tool/sample/make_benchmark_pdf.swift <output.pdf>
import AppKit
import CoreText
var box = CGRect(x: 0, y: 0, width: 595, height: 842)
let context = CGContext(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                       mediaBox: &box, nil)!
for page in 1...300 {
    context.beginPDFPage(nil)
    for line in 0..<45 {
        let text = NSAttributedString(string: "Page \(page) — Line \(line): PDF rendering, selection and scrolling benchmark.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        context.textPosition = CGPoint(x: 40, y: 790 - line * 16)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    context.setFillColor(NSColor(calibratedRed: CGFloat(page % 10) / 10, green: 0.5, blue: 0.7, alpha: 1).cgColor)
    context.fill(CGRect(x: 40, y: 40, width: 515, height: 16))
    context.endPDFPage()
}
context.closePDF()
