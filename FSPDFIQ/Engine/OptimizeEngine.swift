import UIKit
import PDFKit
import CoreImage

enum OptimizeEngine {

    // MARK: Rasterising helpers

    /// Re-builds a PDF with each page as a JPEG image. `transform` can post-process each page image.
    static func rasterPDF(_ doc: PDFDocument, dpi: CGFloat, quality: CGFloat, gray: Bool = false,
                          progress: Progress? = nil, transform: ((CGImage) -> CGImage?)? = nil) throws -> Data {
        let w = PDFWriter()
        let n = doc.pageCount
        guard n > 0 else { throw IQError.noPages }
        for i in 0..<n {
            guard let page = doc.page(at: i) else { continue }
            try autoreleasepool {
                guard var img = Draw.render(page, dpi: dpi, gray: gray) else { throw IQError.saveFailed }
                if let t = transform, let out = t(img) { img = out }
                guard let jd = Draw.jpeg(img, quality: quality), let jimg = Draw.jpegImage(jd) else { throw IQError.saveFailed }
                let size = page.displaySize
                w.page(size) { ctx in ctx.draw(jimg, in: CGRect(origin: .zero, size: size)) }
            }
            progress?(Double(i + 1) / Double(n))
        }
        return w.finish()
    }

    // MARK: Compress

    /// level 0 = light, 1 = balanced, 2 = strong. Returns a summary message.
    static func compress(_ url: URL, level: Int, targetKB: Int?, out: URL, progress: Progress?) throws -> String {
        let doc = try PDFIO.open(url)
        let original = Workspace.size(url)
        var data: Data
        if let kb = targetKB, kb > 0 {
            let target = kb * 1024
            let steps: [(CGFloat, CGFloat)] = [(150, 0.72), (130, 0.62), (110, 0.55), (96, 0.5), (85, 0.42),
                                               (72, 0.38), (72, 0.3), (60, 0.28), (50, 0.24), (42, 0.2)]
            var best: Data? = nil
            for (k, s) in steps.enumerated() {
                let d = try rasterPDF(doc, dpi: s.0, quality: s.1, progress: { p in progress?((Double(k) + p) / Double(steps.count)) })
                if best == nil || d.count < best!.count { best = d }
                if d.count <= target { best = d; break }
            }
            data = best ?? Data()
        } else {
            let (dpi, q): (CGFloat, CGFloat) = level == 0 ? (150, 0.75) : (level == 2 ? (80, 0.45) : (110, 0.6))
            data = try rasterPDF(doc, dpi: dpi, quality: q, progress: progress)
        }
        if targetKB == nil, Int64(data.count) >= original, let orig = try? Data(contentsOf: url) {
            try orig.write(to: out)
            return L("This PDF is already well optimised — the original was kept.",
                     "PDF ini sudah dioptimumkan — fail asal dikekalkan.")
        }
        try data.write(to: out)
        let newSize = Int64(data.count)
        let saved = original > 0 ? Int((1 - Double(newSize) / Double(original)) * 100) : 0
        let a = ByteCountFormatter.string(fromByteCount: original, countStyle: .file)
        let b = ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file)
        var msg = L("\(a) → \(b) (\(max(saved, 0))% smaller)", "\(a) → \(b) (\(max(saved, 0))% lebih kecil)")
        if let kb = targetKB, newSize > Int64(kb * 1024) {
            msg += L(". Couldn't reach \(kb) KB without making it unreadable — this is the smallest readable version.",
                     ". Tidak dapat mencapai \(kb) KB tanpa menjejaskan bacaan — ini versi terkecil yang masih jelas.")
        }
        return msg
    }

    static func grayscale(_ url: URL, out: URL, progress: Progress?) throws {
        let doc = try PDFIO.open(url)
        try rasterPDF(doc, dpi: 150, quality: 0.75, gray: true, progress: progress).write(to: out)
    }

    // MARK: Crop

    struct Insets { var top: CGFloat; var bottom: CGFloat; var left: CGFloat; var right: CGFloat } // fractions 0...0.45

    static func crop(_ url: URL, insets: Insets, range: String, out: URL) throws {
        let doc = try PDFIO.open(url)
        let idx = try PDFIO.parseRange(range, count: doc.pageCount)
        for i in idx {
            guard let p = doc.page(at: i) else { continue }
            let b = p.bounds(for: .cropBox)
            var minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat
            switch p.normalizedRotation {
            case 90:  minX = insets.top; maxY = insets.right; maxX = insets.bottom; minY = insets.left
            case 180: minY = insets.top; minX = insets.right; maxY = insets.bottom; maxX = insets.left
            case 270: maxX = insets.top; minY = insets.right; minX = insets.bottom; maxY = insets.left
            default:  minX = insets.left; maxX = insets.right; minY = insets.bottom; maxY = insets.top
            }
            let r = CGRect(x: b.minX + b.width * minX, y: b.minY + b.height * minY,
                           width: b.width * (1 - minX - maxX), height: b.height * (1 - minY - maxY))
            guard r.width > 10, r.height > 10 else { continue }
            p.setBounds(r, for: .cropBox)
        }
        try PDFIO.write(doc, to: out)
    }

    // MARK: Repair

    static func repair(_ url: URL, out: URL) throws -> String {
        var data = try Data(contentsOf: url)
        if let r = data.range(of: Data("%PDF".utf8)), r.lowerBound > data.startIndex {
            data = data.subdata(in: r.lowerBound..<data.endIndex)
        }
        func rebuild(_ d: PDFDocument) throws -> String {
            let fresh = PDFDocument()
            OrganizeEngine.copyPages(from: d, indices: Array(0..<d.pageCount), into: fresh)
            try PDFIO.write(fresh, to: out)
            return L("Rebuilt the document structure — \(fresh.pageCount) page(s) recovered.",
                     "Struktur dokumen dibina semula — \(fresh.pageCount) halaman dipulihkan.")
        }
        if let d = PDFDocument(data: data), d.pageCount > 0, !d.isLocked { return try rebuild(d) }
        if let r = data.range(of: Data("%%EOF".utf8), options: .backwards) {
            let cut = data.subdata(in: data.startIndex..<r.upperBound)
            if let d = PDFDocument(data: cut), d.pageCount > 0 { return try rebuild(d) }
        }
        // Add a missing %%EOF
        var patched = data
        patched.appendString("\n%%EOF\n")
        if let d = PDFDocument(data: patched), d.pageCount > 0 { return try rebuild(d) }

        // Last resort: salvage embedded JPEG images
        var images: [CGImage] = []
        let bytes = [UInt8](data)
        var i = 0
        let endMarker = [UInt8]("endstream".utf8)
        while i < bytes.count - 3 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF {
                var j = i + 3
                var found = -1
                while j < bytes.count - endMarker.count {
                    if bytes[j] == endMarker[0] && Array(bytes[j..<(j + endMarker.count)]) == endMarker { found = j; break }
                    j += 1
                }
                let end = found > 0 ? found : bytes.count
                let chunk = Data(bytes[i..<end])
                if let ui = UIImage(data: chunk), let cg = ui.cgImage, cg.width > 64, cg.height > 64 { images.append(cg) }
                i = end
            } else { i += 1 }
        }
        guard !images.isEmpty else {
            throw IQError.msg("This file is too damaged to repair.", "Fail ini terlalu rosak untuk dibaiki.")
        }
        let w = PDFWriter()
        for img in images {
            let size = CGSize(width: Paper.a4.width, height: Paper.a4.width * CGFloat(img.height) / CGFloat(img.width))
            w.page(size) { ctx in ctx.draw(img, in: CGRect(origin: .zero, size: size)) }
        }
        try w.finish().write(to: out)
        return L("The page structure was lost, but \(images.count) image(s) were recovered into a new PDF.",
                 "Struktur halaman hilang, tetapi \(images.count) imej berjaya dipulihkan ke PDF baharu.")
    }

    // MARK: Flatten

    static func flatten(_ doc: PDFDocument) -> Data {
        let w = PDFWriter()
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            let s = p.displaySize
            w.page(s) { ctx in Draw.page(p, in: CGRect(origin: .zero, size: s), ctx: ctx, annotations: true) }
        }
        return w.finish()
    }

    static func flatten(_ url: URL, out: URL) throws {
        try flatten(try PDFIO.open(url)).write(to: out)
    }

    // MARK: PDF/A-2b (raster)

    static func pdfa(_ url: URL, out: URL, progress: Progress?) throws {
        let doc = try PDFIO.open(url)
        let n = doc.pageCount
        guard n > 0 else { throw IQError.noPages }
        let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? Workspace.base(url)

        var objects: [Data] = []
        func add(_ d: Data) -> Int { objects.append(d); return objects.count }
        func dict(_ s: String) -> Data { Data(s.utf8) }
        func stream(_ dictBody: String, _ content: Data) -> Data {
            var d = Data("<< \(dictBody) /Length \(content.count) >>\nstream\n".utf8)
            d.append(content)
            d.appendString("\nendstream")
            return d
        }

        // reserve 1 catalog, 2 pages, 3 metadata, 4 icc
        objects = [Data(), Data(), Data(), Data()]
        let icc = (CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?) ?? Data()
        objects[3] = stream("/N 3", icc)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = iso.string(from: Date())
        let xmp = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:pdf="http://ns.adobe.com/pdf/1.3/">
           <pdfaid:part>2</pdfaid:part>
           <pdfaid:conformance>B</pdfaid:conformance>
           <dc:format>application/pdf</dc:format>
           <dc:title><rdf:Alt><rdf:li xml:lang="x-default">\(title.xmlEscaped)</rdf:li></rdf:Alt></dc:title>
           <xmp:CreateDate>\(now)</xmp:CreateDate>
           <xmp:ModifyDate>\(now)</xmp:ModifyDate>
           <xmp:CreatorTool>fs PDF IQ</xmp:CreatorTool>
           <pdf:Producer>fs PDF IQ</pdf:Producer>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        objects[2] = stream("/Type /Metadata /Subtype /XML", Data(xmp.utf8))

        var kids: [Int] = []
        for i in 0..<n {
            guard let page = doc.page(at: i) else { continue }
            try autoreleasepool {
                guard let img = Draw.render(page, dpi: 200), let jpg = Draw.jpeg(img, quality: 0.85) else { throw IQError.saveFailed }
                let size = page.displaySize
                let imObj = add(stream("/Type /XObject /Subtype /Image /Width \(img.width) /Height \(img.height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode", jpg))
                let W = String(format: "%.2f", size.width), H = String(format: "%.2f", size.height)
                let content = "q \(W) 0 0 \(H) 0 0 cm /Im0 Do Q"
                let cObj = add(stream("", Data(content.utf8)))
                let pObj = add(dict("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(W) \(H)] /Resources << /XObject << /Im0 \(imObj) 0 R >> >> /Contents \(cObj) 0 R >>"))
                kids.append(pObj)
            }
            progress?(Double(i + 1) / Double(n))
        }
        objects[1] = dict("<< /Type /Pages /Kids [\(kids.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(kids.count) >>")
        objects[0] = dict("<< /Type /Catalog /Pages 2 0 R /Metadata 3 0 R /OutputIntents [<< /Type /OutputIntent /S /GTS_PDFA1 /OutputConditionIdentifier (sRGB IEC61966-2.1) /Info (sRGB IEC61966-2.1) /DestOutputProfile 4 0 R >>] >>")

        var file = Data("%PDF-1.7\n".utf8)
        file.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets: [Int] = []
        for (k, o) in objects.enumerated() {
            offsets.append(file.count)
            file.appendString("\(k + 1) 0 obj\n")
            file.append(o)
            file.appendString("\nendobj\n")
        }
        let xref = file.count
        file.appendString("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n")
        for off in offsets { file.appendString(String(format: "%010d 00000 n \n", off)) }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        file.appendString("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /ID [<\(id)> <\(id)>] >>\nstartxref\n\(xref)\n%%EOF\n")
        try file.write(to: out)
    }

    // MARK: Magic filter (scans)

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// mode 0 = magic colour, 1 = black & white, 2 = grayscale, 3 = original
    static func enhance(_ image: CGImage, mode: Int) -> CGImage? {
        if mode == 3 { return image }
        var ci = CIImage(cgImage: image)
        let extent = ci.extent
        // Even out shadows: flatten the background illumination, then boost contrast.
        if let enh = CIFilter(name: "CIDocumentEnhancer") {
            enh.setValue(ci, forKey: kCIInputImageKey)
            enh.setValue(1.2, forKey: "inputAmount")
            if let o = enh.outputImage { ci = o }
        }
        if let hs = CIFilter(name: "CIHighlightShadowAdjust") {
            hs.setValue(ci, forKey: kCIInputImageKey)
            hs.setValue(0.9, forKey: "inputShadowAmount")
            hs.setValue(1.0, forKey: "inputHighlightAmount")
            if let o = hs.outputImage { ci = o }
        }
        let cc = CIFilter(name: "CIColorControls")!
        cc.setValue(ci, forKey: kCIInputImageKey)
        switch mode {
        case 1:
            cc.setValue(0.0, forKey: kCIInputSaturationKey)
            cc.setValue(1.9, forKey: kCIInputContrastKey)
            cc.setValue(0.12, forKey: kCIInputBrightnessKey)
        case 2:
            cc.setValue(0.0, forKey: kCIInputSaturationKey)
            cc.setValue(1.2, forKey: kCIInputContrastKey)
            cc.setValue(0.04, forKey: kCIInputBrightnessKey)
        default:
            cc.setValue(1.15, forKey: kCIInputSaturationKey)
            cc.setValue(1.25, forKey: kCIInputContrastKey)
            cc.setValue(0.05, forKey: kCIInputBrightnessKey)
        }
        guard var outImg = cc.outputImage else { return image }
        if let sh = CIFilter(name: "CISharpenLuminance") {
            sh.setValue(outImg, forKey: kCIInputImageKey)
            sh.setValue(0.5, forKey: kCIInputSharpnessKey)
            if let o = sh.outputImage { outImg = o }
        }
        return ciContext.createCGImage(outImg.cropped(to: extent), from: extent)
    }

    static func loadImages(_ urls: [URL], dpi: CGFloat = 200) throws -> [CGImage] {
        var out: [CGImage] = []
        for u in urls {
            if u.pathExtension.lowercased() == "pdf" {
                let d = try PDFIO.open(u)
                for i in 0..<d.pageCount {
                    if let p = d.page(at: i), let img = Draw.render(p, dpi: dpi) { out.append(img) }
                }
            } else if let ui = UIImage(contentsOfFile: u.path), let cg = Draw.normalized(ui).cgImage {
                out.append(cg)
            }
        }
        guard !out.isEmpty else { throw IQError.noInput }
        return out
    }

    /// Images -> A4-width PDF pages (page size follows image aspect).
    static func imagesPDF(_ images: [CGImage], quality: CGFloat = 0.8, a4Fit: Bool = false) throws -> Data {
        let w = PDFWriter()
        for img in images {
            guard let jd = Draw.jpeg(img, quality: quality), let j = Draw.jpegImage(jd) else { continue }
            let aspect = CGFloat(img.height) / CGFloat(max(1, img.width))
            if a4Fit {
                let page = aspect >= 1 ? Paper.a4 : CGSize(width: Paper.a4.height, height: Paper.a4.width)
                let fit = min(page.width / CGFloat(img.width), page.height / CGFloat(img.height))
                let r = CGRect(x: (page.width - CGFloat(img.width) * fit) / 2, y: (page.height - CGFloat(img.height) * fit) / 2,
                               width: CGFloat(img.width) * fit, height: CGFloat(img.height) * fit)
                w.page(page) { ctx in ctx.draw(j, in: r) }
            } else {
                let size = CGSize(width: Paper.a4.width, height: Paper.a4.width * aspect)
                w.page(size) { ctx in ctx.draw(j, in: CGRect(origin: .zero, size: size)) }
            }
        }
        return w.finish()
    }

    static func magic(_ urls: [URL], mode: Int, out: URL, progress: Progress?) throws {
        let imgs = try loadImages(urls)
        var done: [CGImage] = []
        for (i, img) in imgs.enumerated() {
            autoreleasepool { done.append(enhance(img, mode: mode) ?? img) }
            progress?(Double(i + 1) / Double(imgs.count))
        }
        try imagesPDF(done, quality: 0.8).write(to: out)
    }

    // MARK: Slide ink saver

    /// mode 0 = auto (invert dark slides only), 1 = invert every page; grayscale also removes colour.
    static func inkSaver(_ url: URL, mode: Int, grayscale: Bool, out: URL, progress: Progress?) throws {
        let doc = try PDFIO.open(url)
        let data = try rasterPDF(doc, dpi: 150, quality: 0.8, gray: false, progress: progress) { img in
            let dark = Draw.averageLuminance(img) < 0.5
            var ci = CIImage(cgImage: img)
            if mode == 1 || dark, let inv = CIFilter(name: "CIColorInvert") {
                inv.setValue(ci, forKey: kCIInputImageKey)
                if let o = inv.outputImage { ci = o }
            }
            if let cc = CIFilter(name: "CIColorControls") {
                cc.setValue(ci, forKey: kCIInputImageKey)
                cc.setValue(grayscale ? 0.0 : 0.9, forKey: kCIInputSaturationKey)
                cc.setValue(1.15, forKey: kCIInputContrastKey)
                cc.setValue(0.03, forKey: kCIInputBrightnessKey)
                if let o = cc.outputImage { ci = o }
            }
            return ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        try data.write(to: out)
    }

    // MARK: Thesis margins

    /// margins in cm: [left, top, right, bottom]
    static func thesis(_ url: URL, marginsCM: [Double], out: URL) throws {
        let doc = try PDFIO.open(url)
        let m = marginsCM.map { CGFloat($0) * Paper.cm }
        guard m.count == 4 else { return }
        let w = PDFWriter()
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            let landscape = p.displaySize.width > p.displaySize.height
            let size = landscape ? CGSize(width: Paper.a4.height, height: Paper.a4.width) : Paper.a4
            let r = CGRect(x: m[0], y: m[3], width: size.width - m[0] - m[2], height: size.height - m[1] - m[3])
            w.page(size) { ctx in Draw.page(p, in: r, ctx: ctx) }
        }
        try w.finish().write(to: out)
    }

    // MARK: Cornell notes

    static func cornell(_ url: URL, perPage: Int, out: URL) throws {
        let doc = try PDFIO.open(url)
        let n = doc.pageCount
        guard n > 0 else { throw IQError.noPages }
        let size = Paper.a4
        let m: CGFloat = 28
        let ink = UIColor(white: 0.25, alpha: 1)
        let line = UIColor(white: 0.78, alpha: 1)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.fsTeal]
        let headAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .regular), .foregroundColor: ink]
        let per = perPage == 2 ? 2 : 1
        let w = PDFWriter(title: Workspace.base(url) + " – Cornell")
        var i = 0
        while i < n {
            w.page(size) { ctx in
                // header (UIKit coords)
                Draw.text(L("Topic: ____________________________", "Topik: ____________________________"),
                          in: CGRect(x: m, y: m - 6, width: 340, height: 16), pageHeight: size.height, ctx: ctx, attrs: headAttrs)
                Draw.text(L("Date: ______________", "Tarikh: ______________"),
                          in: CGRect(x: size.width - m - 150, y: m - 6, width: 150, height: 16), pageHeight: size.height, ctx: ctx, attrs: headAttrs)
                let top: CGFloat = size.height - m - 18
                let summaryH: CGFloat = 118
                let bottom: CGFloat = m + summaryH
                let cueW: CGFloat = (size.width - 2 * m) * 0.3
                let notesX = m + cueW
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(CGRect(x: m, y: m, width: size.width - 2 * m, height: top - m))
                ctx.move(to: CGPoint(x: notesX, y: top)); ctx.addLine(to: CGPoint(x: notesX, y: bottom)); ctx.strokePath()
                ctx.move(to: CGPoint(x: m, y: bottom)); ctx.addLine(to: CGPoint(x: size.width - m, y: bottom)); ctx.strokePath()

                Draw.text(L("CUES / QUESTIONS", "ISYARAT / SOALAN"), in: CGRect(x: m + 6, y: size.height - top + 4, width: cueW - 12, height: 14),
                          pageHeight: size.height, ctx: ctx, attrs: labelAttrs)
                Draw.text(L("SUMMARY", "RUMUSAN"), in: CGRect(x: m + 6, y: size.height - bottom + 4, width: 200, height: 14),
                          pageHeight: size.height, ctx: ctx, attrs: labelAttrs)

                let blockH = (top - bottom) / CGFloat(per)
                for k in 0..<per {
                    let idx = i + k
                    let blockTop = top - CGFloat(k) * blockH
                    let blockBottom = blockTop - blockH
                    var linesFrom = blockTop - 10
                    if idx < n, let p = doc.page(at: idx) {
                        let maxW = size.width - m - notesX - 16
                        let slideH = min(blockH * 0.55, maxW * p.displaySize.height / max(1, p.displaySize.width))
                        let r = CGRect(x: notesX + 8, y: blockTop - 8 - slideH, width: maxW, height: slideH)
                        let used = Draw.page(p, in: r, ctx: ctx)
                        ctx.setStrokeColor(line.cgColor); ctx.setLineWidth(0.5); ctx.stroke(used)
                        linesFrom = used.minY - 18
                    }
                    ctx.setStrokeColor(line.cgColor)
                    ctx.setLineWidth(0.5)
                    var y = linesFrom
                    while y > blockBottom + 8 {
                        ctx.move(to: CGPoint(x: notesX + 8, y: y)); ctx.addLine(to: CGPoint(x: size.width - m - 8, y: y))
                        y -= 20
                    }
                    ctx.strokePath()
                    if k < per - 1 {
                        ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(0.8)
                        ctx.move(to: CGPoint(x: notesX, y: blockBottom)); ctx.addLine(to: CGPoint(x: size.width - m, y: blockBottom)); ctx.strokePath()
                    }
                }
                ctx.setStrokeColor(line.cgColor); ctx.setLineWidth(0.5)
                var sy = bottom - 34
                while sy > m + 10 {
                    ctx.move(to: CGPoint(x: m + 8, y: sy)); ctx.addLine(to: CGPoint(x: size.width - m - 8, y: sy)); sy -= 20
                }
                ctx.strokePath()
            }
            i += per
        }
        try w.finish().write(to: out)
    }
}
