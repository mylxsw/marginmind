import Cocoa
import FlutterMacOS
import PDFKit

/// Native encoders consume a bounded snapshot; they never inspect the live UI.
final class MapExportChannel {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "marginmind/map_export", binaryMessenger: messenger)
    channel.setMethodCallHandler(Self.handle)
  }

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let width = args["width"] as? NSNumber, let height = args["height"] as? NSNumber,
          width.doubleValue.isFinite, height.doubleValue.isFinite,
          width.doubleValue > 0, height.doubleValue > 0 else {
      result(FlutterError(code: "invalid_scene", message: nil, details: nil)); return
    }
    // Encoding can take time on a large map. Reply on the main queue.
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let data: Data
        switch call.method {
        case "pdf": data = try Self.pdf(args)
        case "png": data = try Self.png(args)
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
        }
        DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "export_failed", message: nil, details: nil)) }
      }
    }
  }

  enum ExportError: Error { case invalidScene }
  private static func number(_ value: Any?) throws -> CGFloat {
    guard let value = value as? NSNumber, value.doubleValue.isFinite else { throw ExportError.invalidScene }
    return CGFloat(value.doubleValue)
  }
  private static func color(_ value: Any?) -> NSColor {
    let argb = (value as? NSNumber)?.uint32Value ?? 0
    return NSColor(srgbRed: CGFloat((argb >> 16) & 255) / 255,
                   green: CGFloat((argb >> 8) & 255) / 255,
                   blue: CGFloat(argb & 255) / 255, alpha: CGFloat((argb >> 24) & 255) / 255)
  }

  static func pdf(_ args: [String: Any]) throws -> Data {
    let width = try number(args["width"]), height = try number(args["height"])
    guard width > 0, height > 0, width <= 1000000, height <= 1000000,
          let commands = args["commands"] as? [[String: Any]] else { throw ExportError.invalidScene }
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data) else { throw ExportError.invalidScene }
    var bounds = CGRect(x: 0, y: 0, width: width, height: height)
    guard let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw ExportError.invalidScene }
    context.beginPDFPage(nil)
    // Flutter uses top-left coordinates; AppKit's flipped context keeps all
    // glyphs upright while matching the layout's baseline coordinates.
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    defer { NSGraphicsContext.restoreGraphicsState() }
    for command in commands {
      context.setFillColor(color(command["color"]).cgColor)
      context.setStrokeColor(color(command["color"]).cgColor)
      switch command["type"] as? String {
      case "box":
        guard let r = command["rect"] as? [NSNumber], r.count == 4 else { throw ExportError.invalidScene }
        let rect = CGRect(x: r[0].doubleValue, y: r[1].doubleValue, width: r[2].doubleValue, height: r[3].doubleValue)
        let radius = try number(command["radius"])
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
      case "curve":
        guard let p = command["points"] as? [NSNumber], p.count == 8 else { throw ExportError.invalidScene }
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: command["dashed"] as? Bool == true ? [5, 4] : [])
        context.move(to: CGPoint(x: p[0].doubleValue, y: p[1].doubleValue))
        context.addCurve(to: CGPoint(x: p[6].doubleValue, y: p[7].doubleValue),
                         control1: CGPoint(x: p[2].doubleValue, y: p[3].doubleValue),
                         control2: CGPoint(x: p[4].doubleValue, y: p[5].doubleValue))
        context.strokePath()
      case "text":
        guard let text = command["text"] as? String else { throw ExportError.invalidScene }
        let fontSize = try number(command["fontSize"])
        let font = command["serif"] as? Bool == true
          ? (NSFont(name: "Songti SC", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize))
          : NSFont.systemFont(ofSize: fontSize, weight: command["bold"] as? Bool == true ? .semibold : .regular)
        let x = try number(command["x"]), y = try number(command["y"])
        // Draw one Flutter-measured line with no native reflow or clipping.
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color(command["color"])])
      case "image":
        guard let bytes = command["bytes"] as? FlutterStandardTypedData,
              let image = NSImage(data: bytes.data) else { throw ExportError.invalidScene }
        let x = try number(command["x"]), y = try number(command["y"])
        let w = try number(command["width"]), h = try number(command["height"])
        image.draw(in: CGRect(x: x, y: y, width: w, height: h), from: .zero,
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      default: throw ExportError.invalidScene
      }
    }
    context.endPDFPage()
    context.closePDF()
    // PDFKit validates the generated document before handing it to the app.
    guard PDFDocument(data: data as Data)?.pageCount == 1 else { throw ExportError.invalidScene }
    return data as Data
  }

  static func png(_ args: [String: Any]) throws -> Data {
    let w = try number(args["width"]), h = try number(args["height"])
    guard w > 0, h > 0, w <= 16384, h <= 16384, w * h <= 32000000,
          let tiles = args["tiles"] as? [[String: Any]],
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ExportError.invalidScene }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.cgContext.clear(CGRect(x: 0, y: 0, width: w, height: h))
    for tile in tiles {
      guard let bytes = tile["bytes"] as? FlutterStandardTypedData,
            let image = NSBitmapImageRep(data: bytes.data)?.cgImage else { throw ExportError.invalidScene }
      let x = try number(tile["x"]), y = try number(tile["y"])
      guard x >= 0, y >= 0, x + CGFloat(image.width) <= w, y + CGFloat(image.height) <= h else {
        throw ExportError.invalidScene
      }
      context.cgContext.draw(image, in: CGRect(x: x, y: h - y - CGFloat(image.height),
        width: CGFloat(image.width), height: CGFloat(image.height)))
    }
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ExportError.invalidScene }
    return data
  }
}
