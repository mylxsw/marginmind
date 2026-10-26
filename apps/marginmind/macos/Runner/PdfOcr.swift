import Cocoa
import CoreText
import PDFKit
import Vision
import FlutterMacOS

/// One page bitmap/request at a time; PDF output always retains vector artwork.
final class PdfOcrEngine {
  struct Line {
    let text: String
    let rect: CGRect // normalized, bottom-left origin, in displayed crop box
  }
  enum Failure: Error { case invalidDocument, invalidRange, render, write }

  static func copyURL(_ source: URL) -> URL {
    source.deletingPathExtension().appendingPathExtension("ocr.pdf")
  }

  static func inspect(_ source: URL) throws -> [String: Any] {
    let copy = copyURL(source)
    let url = FileManager.default.fileExists(atPath: copy.path) ? copy : source
    guard let document = PDFDocument(url: url), !document.isLocked else { throw Failure.invalidDocument }
    var textPages = [Int]()
    for index in 0..<document.pageCount {
      autoreleasepool {
        if !(document.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          textPages.append(index + 1)
        }
      }
    }
    return ["path": url.path, "pageCount": document.pageCount, "textPages": textPages,
            "hasCopy": url == copy]
  }

  /// Same transform is used by Vision's bitmap and the output PDF. Flatten the
  /// crop and rotation into a zero-origin displayed page, as PDFium does.
  static func geometry(_ page: CGPDFPage) -> (CGRect, CGAffineTransform) {
    let crop = page.getBoxRect(.cropBox)
    let rotated = abs(page.rotationAngle % 180) == 90
    let bounds = CGRect(origin: .zero, size: rotated
      ? CGSize(width: crop.height, height: crop.width) : crop.size)
    return (bounds, page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
  }

  static func recognize(_ page: CGPDFPage, languages: [String]) throws -> [Line] {
    let (bounds, transform) = geometry(page)
    guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
      throw Failure.invalidDocument
    }
    // At most 2048² RGBA pixels (~16 MiB), regardless of the page's dimensions.
    let scale = min(3, 2048 / max(bounds.width, bounds.height))
    let width = max(1, Int(ceil(bounds.width * scale)))
    let height = max(1, Int(ceil(bounds.height * scale)))
    guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.render }
    bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
    bitmap.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
    bitmap.concatenate(transform)
    bitmap.drawPDFPage(page)
    guard let image = bitmap.makeImage() else { throw Failure.render }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true
    // perform() finishes the current page before cancellation is observed. This
    // keeps the page intact before the remaining pages are copied.
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
      guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
      return Line(text: text, rect: observation.boundingBox)
    }
  }

  static func draw(_ line: Line, in context: CGContext, bounds: CGRect) {
    let rect = CGRect(x: line.rect.minX * bounds.width, y: line.rect.minY * bounds.height,
                      width: line.rect.width * bounds.width, height: line.rect.height * bounds.height)
    guard rect.width > 0, rect.height > 0 else { return }
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, rect.height, nil)
    let attributed = NSAttributedString(string: line.text, attributes: [.font: font])
    let text = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(text, &ascent, &descent, nil))
    guard width > 0, ascent + descent > 0 else { return }
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: rect.width / width, y: rect.height / (ascent + descent))
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: 0, y: descent)
    context.setTextDrawingMode(.invisible)
    CTLineDraw(text, context)
    context.restoreGState()
  }

  static func run(source: URL, first: Int, last: Int, languages: [String],
                  cancelled: () -> Bool, progress: (Int, Int) -> Void,
                  recognizer: (CGPDFPage, [String]) throws -> [Line] = recognize) throws -> [String: Any] {
    let output = copyURL(source)
    let input = FileManager.default.fileExists(atPath: output.path) ? output : source
    guard let document = CGPDFDocument(input as CFURL), !document.isEncrypted,
          let textDocument = PDFDocument(url: input), !textDocument.isLocked else { throw Failure.invalidDocument }
    guard first >= 1, last >= first, last <= document.numberOfPages else { throw Failure.invalidRange }
    let temporary = output.deletingLastPathComponent().appendingPathComponent(".ocr-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let consumer = CGDataConsumer(url: temporary as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw Failure.write }
    var done = 0
    var wasCancelled = false
    do {
      for number in 1...document.numberOfPages {
        try autoreleasepool {
          guard let page = document.page(at: number) else { throw Failure.invalidDocument }
          let (bounds, transform) = geometry(page)
          guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw Failure.invalidDocument
          }
          context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: [bounds], length: MemoryLayout<CGRect>.size)] as CFDictionary)
          context.saveGState()
          context.concatenate(transform)
          context.drawPDFPage(page)
          context.restoreGState()
          if cancelled() { wasCancelled = true }
          if number >= first && number <= last && !wasCancelled {
            let hasText = !(textDocument.page(at: number - 1)?.string ?? "")
              .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasText {
              for line in try recognizer(page, languages) { draw(line, in: context, bounds: bounds) }
            }
            done += 1
            progress(done, last - first + 1)
          }
          context.endPDFPage()
        }
      }
      context.closePDF()
    } catch {
      context.closePDF()
      throw error
    }
    // POSIX rename atomically replaces an older copy; readers may still hold
    // its inode while the complete new file is installed. Never touch source.
    guard rename(temporary.path, output.path) == 0 else { throw Failure.write }
    var result = try inspect(source)
    result["cancelled"] = wasCancelled || cancelled()
    return result
  }
}

final class PdfOcrChannel {
  private let channel: FlutterMethodChannel
  private let worker: DispatchQueue
  private let inspector = DispatchQueue(label: "marginmind.pdf-ocr.inspect", qos: .userInitiated)
  private let lock = NSLock()
  private var active: String?
  private var cancellation = false

  init(messenger: FlutterBinaryMessenger,
       worker: DispatchQueue = DispatchQueue(label: "marginmind.pdf-ocr", qos: .userInitiated)) {
    self.worker = worker
    channel = FlutterMethodChannel(name: "marginmind/pdf_ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private func isCancelled() -> Bool {
    lock.lock(); defer { lock.unlock() }
    return cancellation
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
    }
    if call.method == "cancel", let id = args["id"] as? String {
      lock.lock()
      if active == id { cancellation = true }
      lock.unlock()
      result(nil); return
    }
    guard ["inspect", "recognize"].contains(call.method),
          let path = args["source"] as? String, path.hasPrefix("/"),
          path.lowercased().hasSuffix(".pdf"), !path.lowercased().hasSuffix(".ocr.pdf") else {
      result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
    }
    let source = URL(fileURLWithPath: path)
    if call.method == "inspect" {
      inspector.async {
        do {
          let value = try PdfOcrEngine.inspect(source)
          DispatchQueue.main.async { result(value) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "read_failed", message: nil, details: nil)) } }
      }
      return
    }
    guard let id = args["id"] as? String, let first = args["first"] as? Int,
          let last = args["last"] as? Int, let languages = args["languages"] as? [String],
          !languages.isEmpty, languages.allSatisfy({ ["zh-Hans", "en-US"].contains($0) }) else {
      result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
    }
    lock.lock()
    if active != nil {
      lock.unlock(); result(FlutterError(code: "busy", message: nil, details: nil)); return
    }
    active = id; cancellation = false
    lock.unlock()
    worker.async {
      var value: Any
      do {
        value = try PdfOcrEngine.run(source: source, first: first, last: last, languages: languages,
          cancelled: self.isCancelled, progress: { done, total in
            DispatchQueue.main.async {
              self.channel.invokeMethod("progress", arguments: ["id": id, "done": done, "total": total])
            }
          })
      } catch { value = FlutterError(code: "recognition_failed", message: nil, details: nil) }
      self.lock.lock(); self.active = nil; self.lock.unlock()
      DispatchQueue.main.async { result(value) }
    }
  }
}
