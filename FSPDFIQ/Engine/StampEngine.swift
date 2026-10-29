import UIKit
import PDFKit

/// Image stamp (signatures, pictures). Drawn by PDFKit on screen and by our flattener.
final class ImageAnnotation: PDFAnnotation {
    var image: UIImage?

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = image?.cgImage else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}

enum StampEngine {
    static let redactTag = "fsiq-redact"

    static let colors: [UIColor] = [UIColor(white: 0.45, alpha: 1), .fsRed, .fsTeal, .black, .systemBlue]

    /// 0 TL, 1 TC, 2 TR, 3 BL, 4 BC, 5 BR
    static func textRect(_ size: CGSize, text: String, attrs: [NSAttributedString.Key: Any], position: Int, margin: CGFloat = 22) -> CGRect {
        let ts = (text as NSString).size(withAttributes: attrs)
        let x: CGFloat
        switch position % 3 {
        case 0: x = margin
        case 1: x = (size.width - ts.width) / 2
        default: x = size.width - margin - ts.width
        }
        let y = position < 3 ? margin * 0.8 : size.height - margin * 0.8 - ts.height
        return CGRect(x: x, y: y, width: ts.width + 2, height: ts.height + 2)
    }

    /// Redraws every page and lets `overlay` draw on top in UIKit coordinates (origin top-left).
    static func overlay(_ url: URL, out: URL, pages: Set<Int>? = nil,
                        _ draw: (_ size: CGSize, _ index: Int, _ count: Int) -> Void) throws {
        let doc = try PDFIO.open(url)
        let w = PDFWriter(title: doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
        let n = doc.pageCount
        for i in 0..<n {
            guard let p = doc.page(at: i) else { continue }
            let s = p.displaySize
            w.page(s) { ctx in
                Draw.page(p, in: CGRect(origin: .zero, size: s), ctx: ctx)
                if pages == nil || pages!.contains(i) {
                    Draw.uikit(ctx, height: s.height) { draw(s, i, n) }
                }
            }
        }
        try w.finish().write(to: out)
    }

    /// format 0 = "1", 1 = "Page 1 of N", 2 = "1 / N", 3 = "- 1 -"
    static func pageNumbers(_ url: URL, position: Int, format: Int, start: Int, fontSize: CGFloat, skipFirst: Bool, out: URL) throws {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor(white: 0.15, alpha: 1)]
        try overlay(url, out: out) { size, i, count in
            if skipFirst && i == 0 { return }
            let num = start + i - (skipFirst ? 1 : 0)
            let total = count - (skipFirst ? 1 : 0) + start - 1
            let text: String
            switch format {
            case 1: text = L("Page \(num) of \(total)", "Halaman \(num) daripada \(total)")
            case 2: text = "\(num) / \(total)"
            case 3: text = "- \(num) -"
            default: text = "\(num)"
            }
            (text as NSString).draw(in: textRect(size, text: text, attrs: attrs, position: position), withAttributes: attrs)
        }
    }

    static func bates(_ url: URL, prefix: String, suffix: String, start: Int, digits: Int, position: Int, fontSize: CGFloat, out: URL) throws {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: UIColor.black]
        try overlay(url, out: out) { size, i, _ in
            let n = String(start + i)
            let padded = String(repeating: "0", count: max(0, digits - n.count)) + n
            let text = prefix + padded + suffix
            let r = textRect(size, text: text, attrs: attrs, position: position, margin: 18)
            UIColor.white.withAlphaComponent(0.85).setFill()
            UIBezierPath(rect: r.insetBy(dx: -3, dy: -1)).fill()
            (text as NSString).draw(in: r, withAttributes: attrs)
        }
    }

    /// style 0 = diagonal, 1 = centre, 2 = tiled
    static func watermark(_ url: URL, text: String, style: Int, colorIndex: Int, opacity: CGFloat, fontSize: CGFloat, range: String, out: URL) throws {
        let doc = try PDFIO.open(url)
        let idx = Set(try PDFIO.parseRange(range, count: doc.pageCount))
        let color = colors[min(max(colorIndex, 0), colors.count - 1)].withAlphaComponent(opacity)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color]
        let t = text.isEmpty ? L("CONFIDENTIAL", "SULIT") : text
        try overlay(url, out: out, pages: idx) { size, _, _ in
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            let ts = (t as NSString).size(withAttributes: attrs)
            switch style {
            case 1:
                (t as NSString).draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
            case 2:
                ctx.saveGState()
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: -.pi / 6)
                let stepX = ts.width + 60, stepY = ts.height + 90
                let span = max(size.width, size.height) * 1.2
                var y = -span
                var row = 0
                while y < span {
                    var x = -span + (row % 2 == 0 ? 0 : stepX / 2)
                    while x < span {
                        (t as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
                        x += stepX
                    }
                    y += stepY; row += 1
                }
                ctx.restoreGState()
            default:
                ctx.saveGState()
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: -atan2(size.height, size.width))
                (t as NSString).draw(at: CGPoint(x: -ts.width / 2, y: -ts.height / 2), withAttributes: attrs)
                ctx.restoreGState()
            }
        }
    }

    static func protect(_ url: URL, password: String, out: URL) throws {
        let doc = try PDFIO.open(url)
        let opts: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        guard doc.write(to: out, withOptions: opts) else { throw IQError.saveFailed }
    }

    static func unlock(_ url: URL, password: String, out: URL) throws {
        guard let doc = PDFDocument(url: url) else { throw IQError.cannotOpen }
        if doc.isLocked {
            guard doc.unlock(withPassword: password) else { throw IQError.wrongPassword }
        }
        let fresh = PDFDocument()
        OrganizeEngine.copyPages(from: doc, indices: Array(0..<doc.pageCount), into: fresh)
        if let attrs = doc.documentAttributes { fresh.documentAttributes = attrs }
        guard let data = fresh.dataRepresentation() else { throw IQError.saveFailed }
        if let check = PDFDocument(data: data), !check.isEncrypted {
            try data.write(to: out)
        } else {
            // Fallback: redraw every page so no encryption survives.
            try OptimizeEngine.flatten(doc).write(to: out)
        }
    }

    static func readMetadata(_ url: URL) -> [String: String] {
        guard let doc = PDFDocument(url: url), let a = doc.documentAttributes else { return [:] }
        var out: [String: String] = [:]
        out["title"] = a[PDFDocumentAttribute.titleAttribute] as? String
        out["author"] = a[PDFDocumentAttribute.authorAttribute] as? String
        out["subject"] = a[PDFDocumentAttribute.subjectAttribute] as? String
        out["creator"] = a[PDFDocumentAttribute.creatorAttribute] as? String
        if let k = a[PDFDocumentAttribute.keywordsAttribute] as? [String] { out["keywords"] = k.joined(separator: ", ") }
        else if let k = a[PDFDocumentAttribute.keywordsAttribute] as? String { out["keywords"] = k }
        return out
    }

    static func writeMetadata(_ url: URL, fields: [String: String], out: URL) throws {
        let doc = try PDFIO.open(url)
        var a = doc.documentAttributes ?? [:]
        a[PDFDocumentAttribute.titleAttribute] = fields["title"] ?? ""
        a[PDFDocumentAttribute.authorAttribute] = fields["author"] ?? ""
        a[PDFDocumentAttribute.subjectAttribute] = fields["subject"] ?? ""
        a[PDFDocumentAttribute.creatorAttribute] = fields["creator"] ?? ""
        let kw = (fields["keywords"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        a[PDFDocumentAttribute.keywordsAttribute] = kw
        a[PDFDocumentAttribute.modificationDateAttribute] = Date()
        doc.documentAttributes = a
        try PDFIO.write(doc, to: out)
    }

    /// True redaction: pages carrying redaction boxes are rasterised with the boxes burnt in.
    static func applyRedactions(_ doc: PDFDocument, progress: Progress? = nil) throws -> Data {
        let w = PDFWriter()
        let n = doc.pageCount
        for i in 0..<n {
            guard let p = doc.page(at: i) else { continue }
            let boxes = p.annotations.filter { $0.userName == redactTag }.map { $0.bounds }
            let others = p.annotations.filter { $0.userName != redactTag }
            let s = p.displaySize
            if boxes.isEmpty {
                w.page(s) { ctx in Draw.page(p, in: CGRect(origin: .zero, size: s), ctx: ctx) }
            } else {
                for a in p.annotations where a.userName == redactTag { a.shouldDisplay = false }
                let img = Draw.render(p, dpi: 200, annotations: true) { ctx in
                    ctx.setFillColor(UIColor.black.cgColor)
                    for b in boxes { ctx.fill(b) }
                }
                for a in p.annotations where a.userName == redactTag { a.shouldDisplay = true }
                _ = others
                guard let im = img, let jd = Draw.jpeg(im, quality: 0.9), let j = Draw.jpegImage(jd) else { throw IQError.saveFailed }
                w.page(s) { ctx in ctx.draw(j, in: CGRect(origin: .zero, size: s)) }
            }
            progress?(Double(i + 1) / Double(n))
        }
        return w.finish()
    }
}
