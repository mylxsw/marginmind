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
  line("26/10/2026, 09:20", 400, 9)
  line("A paragraph continues across pages with English", 300)
  line("words on separate physical lines and 中文内容。", 278)
  line("段内硬换行应该连接，跨页正文应连续阅读。", 256)
  line("This sentence has inter-", 234)
  line("national examples for the excerpt card.", 212)
  line("A second paragraph keeps its paragraph break.", 150)
  line("file:///book.html \(n)/301", 15, 9)
  ctx.endPDFPage()
}
ctx.closePDF()
