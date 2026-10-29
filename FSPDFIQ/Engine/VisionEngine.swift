import UIKit
import PDFKit
import Vision
import CoreText

enum OCREngine {
    struct Line { let text: String; let box: CGRect } // box normalised, origin bottom-left

    static func recognize(_ image: CGImage, malay: Bool) throws -> [Line] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        var wanted = ["en-US"]
        if malay { wanted.insert(contentsOf: ["ms-MY", "id-ID"], at: 0) }
        if let supported = try? req.supportedRecognitionLanguages() {
            let langs = wanted.filter { supported.contains($0) }
            if !langs.isEmpty { req.recognitionLanguages = langs }
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let results = req.results ?? []
        return results.compactMap { obs in
            guard let t = obs.topCandidates(1).first?.string, !t.isEmpty else { return nil }
            return Line(text: t, box: obs.boundingBox)
        }
    }

    static func drawInvisible(_ text: String, in rect: CGRect, ctx: CGContext) {
        guard rect.width > 1, rect.height > 1 else { return }
        let font = CTFontCreateWithName("Helvetica" as CFString, rect.height * 0.85, nil)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        ctx.textMatrix = .identity
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.18)
        if width > 0 { ctx.scaleBy(x: rect.width / width, y: 1) }
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Makes a searchable PDF (page image + invisible text) and a .txt file.
    static func run(_ urls: [URL], malay: Bool, outDir: URL, progress: Progress?) throws -> (pdf: URL, txt: URL, chars: Int) {
        var pages: [(CGImage, CGSize)] = []
        for u in urls {
            if u.pathExtension.lowercased() == "pdf" {
                let d = try PDFIO.open(u)
                for i in 0..<d.pageCount {
                    if let p = d.page(at: i), let img = Draw.render(p, dpi: 220) { pages.append((img, p.displaySize)) }
                }
            } else if let ui = UIImage(contentsOfFile: u.path), let cg = Draw.normalized(ui, maxSide: 3000).cgImage {
                let aspect = CGFloat(cg.height) / CGFloat(max(1, cg.width))
                pages.append((cg, CGSize(width: Paper.a4.width, height: Paper.a4.width * aspect)))
            }
        }
        guard !pages.isEmpty else { throw IQError.noInput }
        let base = Workspace.base(urls[0])
        let w = PDFWriter(title: base)
        var allText = ""
        for (i, (img, size)) in pages.enumerated() {
            try autoreleasepool {
                let lines = try recognize(img, malay: malay)
                guard let jd = Draw.jpeg(img, quality: 0.75), let j = Draw.jpegImage(jd) else { throw IQError.saveFailed }
                w.page(size) { ctx in
                    ctx.draw(j, in: CGRect(origin: .zero, size: size))
                    for l in lines {
                        let r = CGRect(x: l.box.minX * size.width, y: l.box.minY * size.height,
                                       width: l.box.width * size.width, height: l.box.height * size.height)
                        drawInvisible(l.text, in: r, ctx: ctx)
                    }
                }
                if pages.count > 1 { allText += (i == 0 ? "" : "\n\n") + L("— Page \(i + 1) —", "— Halaman \(i + 1) —") + "\n\n" }
                let sorted = lines.sorted { abs($0.box.midY - $1.box.midY) > 0.01 ? $0.box.midY > $1.box.midY : $0.box.minX < $1.box.minX }
                allText += sorted.map { $0.text }.joined(separator: "\n")
            }
            progress?(Double(i + 1) / Double(pages.count))
        }
        let pdf = Workspace.unique(outDir, base + "_OCR.pdf")
        try w.finish().write(to: pdf)
        let txt = Workspace.unique(outDir, base + "_OCR.txt")
        try allText.write(to: txt, atomically: true, encoding: .utf8)
        return (pdf, txt, allText.count)
    }
}

enum CompareEngine {
    /// Side-by-side report with differences highlighted in red. Returns a summary.
    static func compare(_ a: URL, _ b: URL, out: URL, progress: Progress?) throws -> String {
        let da = try PDFIO.open(a), db = try PDFIO.open(b)
        let n = max(da.pageCount, db.pageCount)
        guard n > 0 else { throw IQError.noPages }
        var changed: [Int] = []
        let w = PDFWriter(title: "Compare")
        let sheet = CGSize(width: Paper.a4.height, height: Paper.a4.width)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.darkGray]
        for i in 0..<n {
            try autoreleasepool {
                let pa = i < da.pageCount ? da.page(at: i) : nil
                let pb = i < db.pageCount ? db.page(at: i) : nil
                let refSize = pa?.displaySize ?? pb?.displaySize ?? Paper.a4
                let W = Int(refSize.width * 1.25), H = Int(refSize.height * 1.25)
                func raster(_ p: PDFPage?) -> [UInt8] {
                    var buf = [UInt8](repeating: 255, count: W * H * 4)
                    guard let p = p else { return buf }
                    buf.withUnsafeMutableBytes { ptr in
                        if let c = CGContext(data: ptr.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                            c.setFillColor(UIColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
                            Draw.page(p, in: CGRect(x: 0, y: 0, width: W, height: H), ctx: c)
                        }
                    }
                    return buf
                }
                let ra = raster(pa), rb = raster(pb)
                var mask = [UInt8](repeating: 0, count: W * H * 4)
                var diffCount = 0
                for k in stride(from: 0, to: W * H * 4, by: 4) {
                    let d = abs(Int(ra[k]) - Int(rb[k])) + abs(Int(ra[k + 1]) - Int(rb[k + 1])) + abs(Int(ra[k + 2]) - Int(rb[k + 2]))
                    if d > 90 {
                        diffCount += 1
                        mask[k] = 230; mask[k + 1] = 0; mask[k + 2] = 20; mask[k + 3] = 110
                    }
                }
                let differs = diffCount > (W * H) / 20000 || pa == nil || pb == nil
                if differs { changed.append(i + 1) }
                var maskImage: CGImage? = nil
                if differs {
                    mask.withUnsafeMutableBytes { ptr in
                        if let c = CGContext(data: ptr.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                            maskImage = c.makeImage()
                        }
                    }
                }
                w.page(sheet) { ctx in
                    let half = CGRect(x: 0, y: 0, width: sheet.width / 2, height: sheet.height - 26)
                    let left = half.insetBy(dx: 14, dy: 14)
                    let right = half.offsetBy(dx: sheet.width / 2, dy: 0).insetBy(dx: 14, dy: 14)
                    var usedRight = right
                    if let p = pa { Draw.page(p, in: left, ctx: ctx) }
                    if let p = pb { usedRight = Draw.page(p, in: right, ctx: ctx) }
                    if let m = maskImage { ctx.draw(m, in: usedRight) }
                    ctx.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
                    ctx.stroke(left); ctx.stroke(right)
                    let title = L("Page \(i + 1)", "Halaman \(i + 1)") + (differs ? L("  •  changes highlighted in red", "  •  perubahan ditanda merah") : L("  •  no visible change", "  •  tiada perubahan"))
                    Draw.text("A: \(Workspace.base(a))", in: CGRect(x: 16, y: 8, width: sheet.width / 2 - 30, height: 14), pageHeight: sheet.height, ctx: ctx, attrs: labelAttrs)
                    Draw.text("B: \(Workspace.base(b))   —   " + title, in: CGRect(x: sheet.width / 2 + 16, y: 8, width: sheet.width / 2 - 30, height: 14), pageHeight: sheet.height, ctx: ctx, attrs: labelAttrs)
                }
            }
            progress?(Double(i + 1) / Double(n))
        }
        try w.finish().write(to: out)
        var msg = changed.isEmpty
            ? L("No visible differences found.", "Tiada perbezaan ketara ditemui.")
            : L("Differences on page(s): ", "Perbezaan pada halaman: ") + changed.map(String.init).joined(separator: ", ")
        if da.pageCount != db.pageCount {
            msg += L(". Page counts differ (\(da.pageCount) vs \(db.pageCount)).", ". Bilangan halaman berbeza (\(da.pageCount) lwn \(db.pageCount)).")
        }
        return msg
    }
}
