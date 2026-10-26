// Image-heavy deterministic fixture: 120 pages, each with a distinct 1800x2400 raster.
import AppKit
import CoreText
let w = 1800, h = 2400
var box = CGRect(x: 0, y: 0, width: 600, height: 800)
let pdf = CGContext(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, mediaBox: &box, nil)!
for page in 1...120 {
    autoreleasepool {
        let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for y in stride(from: 0, to: h, by: 12) {
            for x in stride(from: 0, to: w, by: 12) {
                let n = (x * 17 + y * 31 + page * 97) % 255
                bitmap.setFillColor(CGColor(red: CGFloat(n) / 255, green: CGFloat((n + page * 3) % 255) / 255,
                    blue: CGFloat((n * 7) % 255) / 255, alpha: 1))
                bitmap.fill(CGRect(x: x, y: y, width: 10, height: 10))
            }
        }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 0.95))
        bitmap.fill(CGRect(x: 80, y: 100, width: 1640, height: 420))
        let text = NSAttributedString(string: "Raster page \(page) — 1800 × 2400 pixels", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        bitmap.textPosition = CGPoint(x: 120, y: 300)
        CTLineDraw(CTLineCreateWithAttributedString(text), bitmap)
        pdf.beginPDFPage(nil)
        pdf.draw(bitmap.makeImage()!, in: box)
        pdf.endPDFPage()
    }
}
pdf.closePDF()
