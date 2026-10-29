import UIKit
import PDFKit

enum ConvertEngine {

    // MARK: Images -> PDF

    /// pageSize 0 = A4, 1 = Letter, 2 = fit image. orientation 0 = auto, 1 = portrait, 2 = landscape.
    static func imagesToPDF(_ urls: [URL], pageSize: Int, orientation: Int, margin: CGFloat, out: URL, progress: Progress?) throws {
        guard !urls.isEmpty else { throw IQError.noInput }
        let w = PDFWriter()
        var count = 0
        for (i, u) in urls.enumerated() {
            try autoreleasepool {
                guard let ui = UIImage(contentsOfFile: u.path) else { return }
                let img = Draw.normalized(ui)
                guard let jd = img.jpegData(compressionQuality: 0.85), let j = Draw.jpegImage(jd) else { throw IQError.saveFailed }
                let iw = CGFloat(j.width), ih = CGFloat(j.height)
                var page: CGSize
                if pageSize == 2 {
                    page = CGSize(width: Paper.a4.width, height: Paper.a4.width * ih / iw)
                    if iw > ih { page = CGSize(width: Paper.a4.height, height: Paper.a4.height * ih / iw) }
                } else {
                    let base = pageSize == 1 ? Paper.letter : Paper.a4
                    let landscape = orientation == 2 || (orientation == 0 && iw > ih)
                    page = landscape ? CGSize(width: base.height, height: base.width) : base
                }
                let mg = pageSize == 2 ? 0 : margin
                let avail = CGRect(origin: .zero, size: page).insetBy(dx: mg, dy: mg)
                let s = min(avail.width / iw, avail.height / ih)
                let r = CGRect(x: avail.midX - iw * s / 2, y: avail.midY - ih * s / 2, width: iw * s, height: ih * s)
                w.page(page) { ctx in ctx.draw(j, in: r) }
                count += 1
            }
            progress?(Double(i + 1) / Double(urls.count))
        }
        guard count > 0 else { throw IQError.cannotOpen }
        try w.finish().write(to: out)
    }

    // MARK: PDF -> images

    static func pdfToImages(_ url: URL, png: Bool, dpi: CGFloat, quality: CGFloat, transparent: Bool, range: String,
                            outDir: URL, progress: Progress?) throws -> [URL] {
        let doc = try PDFIO.open(url)
        let idx = try PDFIO.parseRange(range, count: doc.pageCount)
        let base = Workspace.base(url)
        var outs: [URL] = []
        for (k, i) in idx.enumerated() {
            try autoreleasepool {
                guard let p = doc.page(at: i), let img = Draw.render(p, dpi: dpi, transparent: png && transparent) else { return }
                let ui = UIImage(cgImage: img)
                guard let data = png ? ui.pngData() : ui.jpegData(compressionQuality: quality) else { throw IQError.saveFailed }
                let u = Workspace.unique(outDir, String(format: "%@_p%03d.%@", base, i + 1, png ? "png" : "jpg"))
                try data.write(to: u)
                outs.append(u)
            }
            progress?(Double(k + 1) / Double(idx.count))
        }
        return outs
    }

    // MARK: PDF -> text

    static func pdfText(_ doc: PDFDocument, pageMarkers: Bool = true) -> String {
        var s = ""
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            if pageMarkers { s += (i == 0 ? "" : "\n\n") + L("— Page \(i + 1) —", "— Halaman \(i + 1) —") + "\n\n" }
            s += p.string ?? ""
        }
        return s
    }

    static func pdfToText(_ url: URL, out: URL) throws -> String {
        let doc = try PDFIO.open(url)
        let text = pdfText(doc)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IQError.msg("No selectable text found. This looks like a scan — try OCR PDF.",
                              "Tiada teks boleh dipilih. Ini kelihatan seperti imbasan — cuba OCR PDF.")
        }
        try text.write(to: out, atomically: true, encoding: .utf8)
        return text
    }

    // MARK: PDF -> Word

    /// Joins visual lines into paragraphs.
    static func paragraphs(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let maxLen = lines.map { $0.count }.max() ?? 0
        var paras: [String] = []
        var current = ""
        for l in lines {
            if l.isEmpty {
                if !current.isEmpty { paras.append(current); current = "" }
                continue
            }
            if current.isEmpty { current = l; continue }
            let prevLong = Double(current.components(separatedBy: "\n").last?.count ?? 0) > Double(maxLen) * 0.6
            let endsSentence = current.hasSuffix(".") || current.hasSuffix(":") || current.hasSuffix("?") || current.hasSuffix("!")
            let bullet = l.hasPrefix("•") || l.hasPrefix("-") || l.hasPrefix("*") || l.range(of: "^[0-9]+[.)]\\s", options: .regularExpression) != nil
            if bullet || (endsSentence && !prevLong) {
                paras.append(current); current = l
            } else if prevLong {
                current += (current.hasSuffix("-") ? "" : " ") + l
            } else {
                current += "\n" + l
            }
        }
        if !current.isEmpty { paras.append(current) }
        return paras
    }

    /// mode 0 = editable text, 1 = exact layout (each page as a picture)
    static func pdfToWord(_ url: URL, mode: Int, out: URL, progress: Progress?) throws {
        let doc = try PDFIO.open(url)
        var w = DocxWriter()
        let n = doc.pageCount
        var anyText = false
        for i in 0..<n {
            guard let p = doc.page(at: i) else { continue }
            if i > 0 { w.pageBreak() }
            if mode == 1 {
                if let img = Draw.render(p, dpi: 150), let jd = Draw.jpeg(img, quality: 0.8) {
                    let maxW: CGFloat = 481.9, maxH: CGFloat = 728.5 // A4 minus 2 cm margins
                    let s = p.displaySize
                    let k = min(maxW / s.width, maxH / s.height)
                    w.image(jpeg: jd, widthPt: s.width * k, heightPt: s.height * k)
                }
            } else {
                let text = p.string ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { anyText = true }
                for para in paragraphs(from: text) { w.paragraph(para) }
            }
            progress?(Double(i + 1) / Double(n))
        }
        if mode == 0 && !anyText {
            throw IQError.msg("No selectable text found (scanned PDF). Use OCR PDF first, or choose 'Exact layout'.",
                              "Tiada teks boleh dipilih (PDF imbasan). Gunakan OCR PDF dahulu, atau pilih 'Susun atur tepat'.")
        }
        try w.build(marginTwips: mode == 1 ? 567 : 1134).write(to: out)
    }

    // MARK: PDF -> Excel

    struct Glyph { let ch: Character; let rect: CGRect }

    /// Groups characters into rows and cells using their positions.
    static func tableRows(for page: PDFPage) -> [[(x: CGFloat, text: String)]] {
        var glyphs: [Glyph] = []
        var heights: [CGFloat] = []
        let count = page.numberOfCharacters
        for i in 0..<count {
            guard let sel = page.selection(for: NSRange(location: i, length: 1)), let s = sel.string, let ch = s.first else { continue }
            if ch.isWhitespace || ch.isNewline { continue }
            let r = sel.bounds(for: page)
            if r.width <= 0 || r.height <= 0 { continue }
            glyphs.append(Glyph(ch: ch, rect: r))
            heights.append(r.height)
        }
        guard !glyphs.isEmpty else { return [] }
        let medH = heights.sorted()[heights.count / 2]
        // rows
        let sorted = glyphs.sorted { $0.rect.midY > $1.rect.midY }
        var rows: [[Glyph]] = []
        var rowY: [CGFloat] = []
        for g in sorted {
            if let last = rowY.last, abs(last - g.rect.midY) < medH * 0.5 {
                rows[rows.count - 1].append(g)
            } else {
                rows.append([g]); rowY.append(g.rect.midY)
            }
        }
        let gapThreshold = max(medH * 0.9, 6)
        let spaceThreshold = medH * 0.18
        var out: [[(x: CGFloat, text: String)]] = []
        for row in rows {
            let r = row.sorted { $0.rect.minX < $1.rect.minX }
            var cells: [(x: CGFloat, text: String)] = []
            var cur = ""
            var curX = r[0].rect.minX
            var lastMax = r[0].rect.minX
            for g in r {
                let gap = g.rect.minX - lastMax
                if !cur.isEmpty && gap > gapThreshold {
                    cells.append((curX, cur)); cur = ""; curX = g.rect.minX
                } else if !cur.isEmpty && gap > spaceThreshold {
                    cur += " "
                }
                cur.append(g.ch)
                lastMax = max(lastMax, g.rect.maxX)
            }
            if !cur.isEmpty { cells.append((curX, cur)) }
            out.append(cells)
        }
        return out
    }

    /// Aligns cells into shared columns.
    static func grid(_ rows: [[(x: CGFloat, text: String)]]) -> [[String]] {
        var starts = rows.flatMap { $0.map { $0.x } }.sorted()
        guard !starts.isEmpty else { return [] }
        var anchors: [CGFloat] = []
        var group: [CGFloat] = [starts.removeFirst()]
        for s in starts {
            if s - (group.last ?? s) < 14 { group.append(s) }
            else { anchors.append(group.reduce(0, +) / CGFloat(group.count)); group = [s] }
        }
        anchors.append(group.reduce(0, +) / CGFloat(group.count))
        return rows.map { cells in
            var line = [String](repeating: "", count: anchors.count)
            for c in cells {
                var best = 0
                var bestD = CGFloat.greatestFiniteMagnitude
                for (k, a) in anchors.enumerated() {
                    let d = abs(a - c.x)
                    if d < bestD { bestD = d; best = k }
                }
                line[best] = line[best].isEmpty ? c.text : line[best] + " " + c.text
            }
            while let l = line.last, l.isEmpty { line.removeLast() }
            return line
        }
    }

    static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return s
    }

    static func pdfToExcel(_ url: URL, oneSheet: Bool, outDir: URL, progress: Progress?) throws -> [URL] {
        let doc = try PDFIO.open(url)
        let base = Workspace.base(url)
        var x = XlsxWriter()
        var all: [[String]] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            let g = grid(tableRows(for: p))
            if oneSheet { all.append(contentsOf: g) } else if !g.isEmpty { x.sheets.append(.init(name: L("Page \(i + 1)", "Halaman \(i + 1)"), rows: g)) }
            progress?(Double(i + 1) / Double(doc.pageCount))
        }
        if oneSheet { x.sheets = [.init(name: base, rows: all)] }
        guard x.sheets.contains(where: { !$0.rows.isEmpty }) else {
            throw IQError.msg("No table text found. If this is a scan, run OCR PDF first.",
                              "Tiada teks jadual ditemui. Jika ini imbasan, jalankan OCR PDF dahulu.")
        }
        let xl = Workspace.unique(outDir, base + ".xlsx")
        try x.build().write(to: xl)
        let csvRows = x.sheets.flatMap { $0.rows }
        let csv = csvRows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\n")
        let cu = Workspace.unique(outDir, base + ".csv")
        try csv.write(to: cu, atomically: true, encoding: .utf8)
        return [xl, cu]
    }

    // MARK: PDF -> PowerPoint

    static func pdfToPPTX(_ url: URL, out: URL, progress: Progress?) throws {
        let doc = try PDFIO.open(url)
        guard let first = doc.page(at: 0) else { throw IQError.noPages }
        var w = PptxWriter()
        let fs = first.displaySize
        let cx = 12_192_000
        let cy = max(914_400, min(51_206_400, Int(Double(cx) * Double(fs.height / max(1, fs.width)))))
        w.slideSizeEMU = (cx, cy)
        for i in 0..<doc.pageCount {
            try autoreleasepool {
                guard let p = doc.page(at: i), let img = Draw.render(p, dpi: 170), let jd = Draw.jpeg(img, quality: 0.85) else { return }
                let s = p.displaySize
                let k = min(Double(cx) / Double(s.width), Double(cy) / Double(s.height))
                let pw = Int(Double(s.width) * k), ph = Int(Double(s.height) * k)
                w.slides.append((jd, (cx - pw) / 2, (cy - ph) / 2, pw, ph))
            }
            progress?(Double(i + 1) / Double(doc.pageCount))
        }
        try w.build().write(to: out)
    }

    // MARK: Extract embedded images

    static func extractImages(_ url: URL, outDir: URL, progress: Progress?) throws -> [URL] {
        guard let cg = CGPDFDocument(url as CFURL) else { throw IQError.cannotOpen }
        if cg.isEncrypted && !cg.isUnlocked { _ = cg.unlockWithPassword("") }
        guard cg.isUnlocked else { throw IQError.locked }
        let base = Workspace.base(url)
        var seen = Set<Int>()
        var outs: [URL] = []
        let n = cg.numberOfPages
        guard n > 0 else { throw IQError.noPages }

        func handleXObjects(_ resources: CGPDFDictionaryRef, page: Int, depth: Int) {
            var xo: CGPDFDictionaryRef? = nil
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xo), let xobjs = xo else { return }
            CGPDFDictionaryApplyBlock(xobjs, { _, obj, _ in
                var stream: CGPDFStreamRef? = nil
                guard CGPDFObjectGetValue(obj, .stream, &stream), let st = stream else { return true }
                let key = Int(bitPattern: st)
                if seen.contains(key) { return true }
                seen.insert(key)
                guard let sd = CGPDFStreamGetDictionary(st) else { return true }
                var namePtr: UnsafePointer<Int8>? = nil
                guard CGPDFDictionaryGetName(sd, "Subtype", &namePtr), let np = namePtr else { return true }
                let subtype = String(cString: np)
                if subtype == "Form", depth < 2 {
                    var res: CGPDFDictionaryRef? = nil
                    if CGPDFDictionaryGetDictionary(sd, "Resources", &res), let r = res { handleXObjects(r, page: page, depth: depth + 1) }
                    return true
                }
                guard subtype == "Image" else { return true }
                var fmt = CGPDFDataFormat.raw
                guard let cfData = CGPDFStreamCopyData(st, &fmt) else { return true }
                let data = cfData as Data
                var ext = "png"
                var out: Data? = nil
                switch fmt {
                case .jpegEncoded: ext = "jpg"; out = data
                case .JPEG2000: ext = "jp2"; out = data
                default:
                    out = rawImageToPNG(sd, data)
                }
                if let o = out {
                    let u = Workspace.unique(outDir, String(format: "%@_p%03d_img%02d.%@", base, page, outs.count + 1, ext))
                    if (try? o.write(to: u)) != nil { outs.append(u) }
                }
                return true
            }, nil)
        }

        for i in 1...n {
            autoreleasepool {
                if let page = cg.page(at: i), let dict = page.dictionary {
                    var res: CGPDFDictionaryRef? = nil
                    if CGPDFDictionaryGetDictionary(dict, "Resources", &res), let r = res { handleXObjects(r, page: i, depth: 0) }
                }
            }
            progress?(Double(i) / Double(n))
        }
        guard !outs.isEmpty else { throw IQError.nothingFound }
        return outs
    }

    private static func rawImageToPNG(_ sd: CGPDFDictionaryRef, _ data: Data) -> Data? {
        var w: CGPDFInteger = 0, h: CGPDFInteger = 0, bpc: CGPDFInteger = 8
        guard CGPDFDictionaryGetInteger(sd, "Width", &w), CGPDFDictionaryGetInteger(sd, "Height", &h), w > 0, h > 0 else { return nil }
        _ = CGPDFDictionaryGetInteger(sd, "BitsPerComponent", &bpc)
        var comps = 3
        var space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        var csName: UnsafePointer<Int8>? = nil
        if CGPDFDictionaryGetName(sd, "ColorSpace", &csName), let c = csName {
            switch String(cString: c) {
            case "DeviceGray", "CalGray": comps = 1; space = CGColorSpaceCreateDeviceGray()
            case "DeviceCMYK": comps = 4; space = CGColorSpaceCreateDeviceCMYK()
            default: comps = 3
            }
        } else {
            var arr: CGPDFArrayRef? = nil
            if CGPDFDictionaryGetArray(sd, "ColorSpace", &arr), let a = arr {
                var nm: UnsafePointer<Int8>? = nil
                if CGPDFArrayGetName(a, 0, &nm), let nmp = nm {
                    let name = String(cString: nmp)
                    if name == "ICCBased" {
                        var st: CGPDFStreamRef? = nil
                        if CGPDFArrayGetStream(a, 1, &st), let s = st, let d = CGPDFStreamGetDictionary(s) {
                            var nc: CGPDFInteger = 3
                            _ = CGPDFDictionaryGetInteger(d, "N", &nc)
                            comps = nc
                            space = nc == 1 ? CGColorSpaceCreateDeviceGray() : (nc == 4 ? CGColorSpaceCreateDeviceCMYK() : CGColorSpaceCreateDeviceRGB())
                        }
                    } else if name == "Indexed" {
                        return nil
                    }
                }
            }
        }
        guard bpc == 8, data.count >= w * h * comps else { return nil }
        guard let provider = CGDataProvider(data: data as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8 * comps, bytesPerRow: w * comps,
                                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        if comps == 4 {
            // Convert CMYK to RGB for PNG
            guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let rgb = c.makeImage() else { return nil }
            return UIImage(cgImage: rgb).pngData()
        }
        return UIImage(cgImage: img).pngData()
    }

    // MARK: PDF -> DXF (CAD)

    static func pdfToDXF(_ url: URL, millimetres: Bool, outDir: URL, progress: Progress?) throws -> [URL] {
        let doc = try PDFIO.open(url)
        let base = Workspace.base(url)
        let k: CGFloat = millimetres ? 25.4 / 72 : 1
        var outs: [URL] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            var dxf = "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n9\n$INSUNITS\n70\n\(millimetres ? 4 : 0)\n0\nENDSEC\n"
            dxf += "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n70\n2\n"
            dxf += "0\nLAYER\n2\nGEOMETRY\n70\n0\n62\n7\n6\nCONTINUOUS\n"
            dxf += "0\nLAYER\n2\nTEXT\n70\n0\n62\n1\n6\nCONTINUOUS\n0\nENDTAB\n0\nENDSEC\n"
            dxf += "0\nSECTION\n2\nENTITIES\n"
            var lines = 0
            if let ref = p.pageRef {
                let segs = VectorCollector.collect(ref)
                for s in segs {
                    dxf += String(format: "0\nLINE\n8\nGEOMETRY\n10\n%.4f\n20\n%.4f\n30\n0.0\n11\n%.4f\n21\n%.4f\n31\n0.0\n",
                                  s.0.x * k, s.0.y * k, s.1.x * k, s.1.y * k)
                    lines += 1
                }
            }
            if let sel = p.selection(for: p.bounds(for: .mediaBox)) {
                for line in sel.selectionsByLine() {
                    guard let t = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
                    let b = line.bounds(for: p)
                    let clean = t.replacingOccurrences(of: "\n", with: " ")
                    dxf += String(format: "0\nTEXT\n8\nTEXT\n10\n%.4f\n20\n%.4f\n30\n0.0\n40\n%.4f\n1\n", b.minX * k, b.minY * k, max(1, b.height * 0.72) * k) + clean + "\n"
                    lines += 1
                }
            }
            dxf += "0\nENDSEC\n0\nEOF\n"
            if lines == 0 { continue }
            let name = doc.pageCount == 1 ? "\(base).dxf" : String(format: "%@_p%03d.dxf", base, i + 1)
            let u = Workspace.unique(outDir, name)
            try dxf.write(to: u, atomically: true, encoding: .utf8)
            outs.append(u)
            progress?(Double(i + 1) / Double(doc.pageCount))
        }
        guard !outs.isEmpty else {
            throw IQError.msg("No vector lines or text were found. Scanned drawings can't be converted to CAD lines.",
                              "Tiada garisan vektor atau teks ditemui. Lukisan imbasan tidak boleh ditukar kepada garisan CAD.")
        }
        return outs
    }
}

// MARK: - Vector path collector for DXF export

final class VectorCollector {
    var ctm = CGAffineTransform.identity
    var stack: [CGAffineTransform] = []
    var path: [(CGPoint, CGPoint)] = []
    var segments: [(CGPoint, CGPoint)] = []
    var cp = CGPoint.zero
    var start = CGPoint.zero

    func moveTo(_ p: CGPoint) { cp = p; start = p }
    func lineTo(_ p: CGPoint) { path.append((cp, p)); cp = p }
    func curveTo(_ c1: CGPoint, _ c2: CGPoint, _ p: CGPoint) {
        let p0 = cp
        var prev = p0
        for k in 1...8 {
            let t = CGFloat(k) / 8, u = 1 - t
            let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p.x
            let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p.y
            let q = CGPoint(x: x, y: y)
            path.append((prev, q)); prev = q
        }
        cp = p
    }
    func close() { if cp != start { path.append((cp, start)) }; cp = start }
    func paint() {
        for s in path {
            let a = s.0.applying(ctm), b = s.1.applying(ctm)
            if abs(a.x - b.x) + abs(a.y - b.y) > 0.01 { segments.append((a, b)) }
        }
        path.removeAll()
    }
    func discard() { path.removeAll() }

    static func pop(_ s: CGPDFScannerRef) -> CGFloat {
        var v: CGPDFReal = 0
        _ = CGPDFScannerPopNumber(s, &v)
        return CGFloat(v)
    }

    static func me(_ info: UnsafeMutableRawPointer?) -> VectorCollector {
        Unmanaged<VectorCollector>.fromOpaque(info!).takeUnretainedValue()
    }

    static func collect(_ page: CGPDFPage) -> [(CGPoint, CGPoint)] {
        let c = VectorCollector()
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in let c = VectorCollector.me(info); c.stack.append(c.ctm) }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in let c = VectorCollector.me(info); if let t = c.stack.popLast() { c.ctm = t } }
        CGPDFOperatorTableSetCallback(table, "cm") { s, info in
            let c = VectorCollector.me(info)
            let f = VectorCollector.pop(s), e = VectorCollector.pop(s), d = VectorCollector.pop(s), cc = VectorCollector.pop(s), b = VectorCollector.pop(s), a = VectorCollector.pop(s)
            c.ctm = CGAffineTransform(a: a, b: b, c: cc, d: d, tx: e, ty: f).concatenating(c.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "m") { s, info in let y = VectorCollector.pop(s), x = VectorCollector.pop(s); VectorCollector.me(info).moveTo(CGPoint(x: x, y: y)) }
        CGPDFOperatorTableSetCallback(table, "l") { s, info in let y = VectorCollector.pop(s), x = VectorCollector.pop(s); VectorCollector.me(info).lineTo(CGPoint(x: x, y: y)) }
        CGPDFOperatorTableSetCallback(table, "c") { s, info in
            let y3 = VectorCollector.pop(s), x3 = VectorCollector.pop(s), y2 = VectorCollector.pop(s), x2 = VectorCollector.pop(s), y1 = VectorCollector.pop(s), x1 = VectorCollector.pop(s)
            VectorCollector.me(info).curveTo(CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2), CGPoint(x: x3, y: y3))
        }
        CGPDFOperatorTableSetCallback(table, "v") { s, info in
            let c = VectorCollector.me(info)
            let y3 = VectorCollector.pop(s), x3 = VectorCollector.pop(s), y2 = VectorCollector.pop(s), x2 = VectorCollector.pop(s)
            c.curveTo(c.cp, CGPoint(x: x2, y: y2), CGPoint(x: x3, y: y3))
        }
        CGPDFOperatorTableSetCallback(table, "y") { s, info in
            let y3 = VectorCollector.pop(s), x3 = VectorCollector.pop(s), y1 = VectorCollector.pop(s), x1 = VectorCollector.pop(s)
            let p = CGPoint(x: x3, y: y3)
            VectorCollector.me(info).curveTo(CGPoint(x: x1, y: y1), p, p)
        }
        CGPDFOperatorTableSetCallback(table, "h") { _, info in VectorCollector.me(info).close() }
        CGPDFOperatorTableSetCallback(table, "re") { s, info in
            let c = VectorCollector.me(info)
            let h = VectorCollector.pop(s), w = VectorCollector.pop(s), y = VectorCollector.pop(s), x = VectorCollector.pop(s)
            c.moveTo(CGPoint(x: x, y: y)); c.lineTo(CGPoint(x: x + w, y: y)); c.lineTo(CGPoint(x: x + w, y: y + h)); c.lineTo(CGPoint(x: x, y: y + h)); c.close()
        }
        for op in ["S", "f", "F", "f*", "B", "B*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in VectorCollector.me(info).paint() }
        }
        for op in ["s", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in let c = VectorCollector.me(info); c.close(); c.paint() }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in VectorCollector.me(info).discard() }

        let stream = CGPDFContentStreamCreateWithPage(page)
        let info = Unmanaged.passUnretained(c).toOpaque()
        let scanner = CGPDFScannerCreate(stream, table, info)
        _ = CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        return c.segments
    }
}
