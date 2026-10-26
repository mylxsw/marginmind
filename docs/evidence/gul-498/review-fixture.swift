// Reproduce: swift fixture.swift fixture.pdf. Three pages with repeated margins.
import AppKit
import CoreText
var box = CGRect(x: 0, y: 0, width: 595, height: 420)
let ctx = CGContext(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, mediaBox: &box, nil)!
func line(_ text: String, _ y: Double, _ size: Double = 14) {
  let value = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
  ctx.textPosition = CGPoint(x: 45, y: y)
  CTLineDraw(CTLineCreateWithAttributedString(value), ctx)
}
for n in 1...3 {
  ctx.beginPDFPage(nil)
  line("A paragraph continues across pages with English", 300)
  line("words on separate physical lines and 中文内容。", 278)
  line("段内硬换行应该连接，跨页正文应连续阅读。", 256)
  line("This sentence has inter-", 234)
  line("national examples for the excerpt card.", 212)
  line("A second paragraph keeps its paragraph break.", 150)
  // Margins drawn after body text, deliberately out of geometric order.
  line("https://example.test/book2 \(n)/12", 15, 9)
  line("\(n + 11)  Book Title", 400, 9)
  ctx.endPDFPage()
}
ctx.closePDF()
