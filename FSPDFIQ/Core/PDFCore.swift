import UIKit
import PDFKit
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Workspace (temporary files)

enum Workspace {
    static let root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("FSPDFIQ", isDirectory: true)

    static func newDir(_ kind: String) -> URL {
        let u = root.appendingPathComponent(kind, isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func unique(_ dir: URL, _ name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)")
            i += 1
        }
        return url
    }

    /// Copies picked/shared files into the app sandbox so they stay readable.
    static func importCopies(_ urls: [URL]) -> [URL] {
        let dir = newDir("In")
        return urls.compactMap { src in
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            let dst = unique(dir, src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dst)
                return dst
            } catch {
                if let d = try? Data(contentsOf: src), (try? d.write(to: dst)) != nil { return dst }
                return nil
            }
        }
    }

    static func saveData(_ data: Data, name: String) -> URL? {
        let url = unique(newDir("In"), name)
        do { try data.write(to: url); return url } catch { return nil }
    }

    static func base(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    static func sizeString(_ url: URL) -> String {
        let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func size(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func clearOld() {
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Opening / saving

enum PDFIO {
    static func open(_ url: URL, password: String? = nil) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw IQError.cannotOpen }
        if doc.isLocked {
            if let p = password, !p.isEmpty, doc.unlock(withPassword: p) { return doc }
            throw IQError.locked
        }
        return doc
    }

    static func write(_ doc: PDFDocument, to url: URL) throws {
        guard let data = doc.dataRepresentation() else { throw IQError.saveFailed }
        try data.write(to: url)
    }

    static func pageCount(_ url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    /// "1-3, 5, 8-" -> zero-based indices. Empty string = all pages.
    static func parseRange(_ s: String, count: Int) throws -> [Int] {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return Array(0..<count) }
        var out: [Int] = []
        for group in parseGroups(t) {
            out.append(contentsOf: try parseGroup(group, count: count))
        }
        if out.isEmpty { throw IQError.badRange }
        return out
    }

    static func parseGroups(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func parseGroup(_ p: String, count: Int) throws -> [Int] {
        let cleaned = p.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: " ", with: "")
        if cleaned.contains("-") {
            let ends = cleaned.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard ends.count == 2 else { throw IQError.badRange }
            let a = ends[0].isEmpty ? 1 : Int(ends[0])
            let b = ends[1].isEmpty ? count : Int(ends[1])
            guard let lo = a, let hi = b, lo >= 1, hi >= lo, lo <= count else { throw IQError.badRange }
            return Array((lo - 1)..<min(hi, count))
        } else {
            guard let n = Int(cleaned), n >= 1, n <= count else { throw IQError.badRange }
            return [n - 1]
        }
    }
}

// MARK: - Page geometry & drawing

extension PDFPage {
    var normalizedRotation: Int { ((rotation % 360) + 360) % 360 }

    /// Size of the page as it is displayed (crop box, rotation applied).
    var displaySize: CGSize {
        let b = bounds(for: .cropBox)
        let r = normalizedRotation
        return (r == 90 || r == 270) ? CGSize(width: b.height, height: b.width) : b.size
    }
}

enum Draw {
    /// Transform that maps page space into `rect` (y-up context), applying crop box, rotation and fit-scaling.
    static func transform(for page: PDFPage, in rect: CGRect) -> (CGAffineTransform, CGRect) {
        let b = page.bounds(for: .cropBox)
        let w = b.width, h = b.height
        let disp = page.displaySize
        guard disp.width > 0, disp.height > 0 else { return (.identity, rect) }
        let s = min(rect.width / disp.width, rect.height / disp.height)
        let ox = rect.minX + (rect.width - disp.width * s) / 2
        let oy = rect.minY + (rect.height - disp.height * s) / 2
        var rot = CGAffineTransform.identity
        switch page.normalizedRotation {
        case 90: rot = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 180: rot = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 270: rot = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        default: break
        }
        let t = CGAffineTransform(translationX: -b.minX, y: -b.minY)
            .concatenating(rot)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: ox, y: oy))
        return (t, CGRect(x: ox, y: oy, width: disp.width * s, height: disp.height * s))
    }

    /// Draws a PDF page (vector) into a y-up context, fitted into `rect`. Returns the rect actually used.
    @discardableResult
    static func page(_ page: PDFPage, in rect: CGRect, ctx: CGContext, annotations: Bool = true,
                     pageSpaceOverlay: ((CGContext) -> Void)? = nil) -> CGRect {
        let (t, used) = transform(for: page, in: rect)
        ctx.saveGState()
        ctx.concatenate(t)
        ctx.clip(to: page.bounds(for: .cropBox))
        if let ref = page.pageRef {
            ctx.drawPDFPage(ref)
            if annotations {
                for a in page.annotations {
                    let type = a.type ?? ""
                    if type == "Popup" || type == "Link" { continue }
                    if !a.shouldDisplay { continue }
                    a.draw(with: .cropBox, in: ctx)
                }
            }
        } else {
            page.draw(with: .cropBox, to: ctx)
        }
        pageSpaceOverlay?(ctx)
        ctx.restoreGState()
        return used
    }

    /// Run UIKit drawing (top-left origin) inside a y-up CG context of the given height.
    static func uikit(_ ctx: CGContext, height: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        body()
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    /// Rasterise a page. Returns nil on failure.
    static func render(_ page: PDFPage, dpi: CGFloat, gray: Bool = false, transparent: Bool = false,
                       annotations: Bool = true, pageSpaceOverlay: ((CGContext) -> Void)? = nil) -> CGImage? {
        let size = page.displaySize
        var scale = dpi / 72
        let maxPixels: CGFloat = 40_000_000
        if size.width * scale * size.height * scale > maxPixels {
            scale = sqrt(maxPixels / max(1, size.width * size.height))
        }
        let W = max(1, Int((size.width * scale).rounded()))
        let H = max(1, Int((size.height * scale).rounded()))
        let space: CGColorSpace = gray ? CGColorSpaceCreateDeviceGray() : (CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB())
        let info: UInt32 = gray ? CGImageAlphaInfo.none.rawValue
            : (transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: info) else { return nil }
        if !transparent {
            c.setFillColor(gray ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            c.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        c.interpolationQuality = .high
        c.setShouldAntialias(true)
        c.scaleBy(x: CGFloat(W) / size.width, y: CGFloat(H) / size.height)
        Draw.page(page, in: CGRect(origin: .zero, size: size), ctx: c, annotations: annotations, pageSpaceOverlay: pageSpaceOverlay)
        return c.makeImage()
    }

    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// CGImage backed by JPEG data — Quartz embeds it as-is (DCTDecode) when drawn into a PDF.
    static func jpegImage(_ data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Text in a y-up page: rect is given in top-left (UIKit) coordinates.
    static func text(_ s: String, in rect: CGRect, pageHeight: CGFloat, ctx: CGContext, attrs: [NSAttributedString.Key: Any]) {
        uikit(ctx, height: pageHeight) {
            (s as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    /// Average luminance (0...1) of an image.
    static func averageLuminance(_ image: CGImage) -> CGFloat {
        var px = [UInt8](repeating: 0, count: 4)
        guard let c = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return 1 }
        c.interpolationQuality = .medium
        c.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.299 * CGFloat(px[0]) + 0.587 * CGFloat(px[1]) + 0.114 * CGFloat(px[2])) / 255
    }

    static func normalized(_ img: UIImage, maxSide: CGFloat = 3200) -> UIImage {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return img }
        let px = CGSize(width: s.width * img.scale, height: s.height * img.scale)
        let k = min(1, maxSide / max(px.width, px.height))
        let ns = CGSize(width: floor(px.width * k), height: floor(px.height * k))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: ns, format: fmt).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: ns))
            img.draw(in: CGRect(origin: .zero, size: ns))
        }
    }
}

// MARK: - PDF writer (CoreGraphics, y-up)

final class PDFWriter {
    private let data = NSMutableData()
    let ctx: CGContext

    init(title: String? = nil) {
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        var info: [CFString: Any] = [kCGPDFContextCreator: "fs PDF IQ"]
        if let t = title { info[kCGPDFContextTitle] = t }
        ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
    }

    func page(_ size: CGSize, _ body: (CGContext) -> Void) {
        var box = CGRect(origin: .zero, size: size)
        let boxData = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
        let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: boxData]
        ctx.beginPDFPage(pageInfo as CFDictionary)
        body(ctx)
        ctx.endPDFPage()
    }

    func finish() -> Data {
        ctx.closePDF()
        return data as Data
    }
}

enum Paper {
    static let a4 = CGSize(width: 595.28, height: 841.89)
    static let letter = CGSize(width: 612, height: 792)
    static let cm: CGFloat = 28.3465
}

extension String {
    var xmlEscaped: String {
        var s = ""
        s.reserveCapacity(count)
        for ch in unicodeScalars {
            switch ch {
            case "&": s += "&amp;"
            case "<": s += "&lt;"
            case ">": s += "&gt;"
            case "\"": s += "&quot;"
            case "'": s += "&apos;"
            default:
                // drop control characters that are illegal in XML 1.0
                if ch.value < 0x20 && ch != "\t" && ch != "\n" && ch != "\r" { continue }
                if ch.value == 0xFFFE || ch.value == 0xFFFF { continue }
                s.unicodeScalars.append(ch)
            }
        }
        return s
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension Data {
    mutating func appendString(_ s: String) { append(contentsOf: Array(s.utf8)) }
}
