import UIKit
import PDFKit

/// Runs every engine on generated sample files. Triggered with the `-selftest` launch argument (used by CI on the simulator).
enum SelfTest {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-selftest") }

    static func log(_ s: String) {
        print("SELFTEST " + s)
        fflush(stdout)
    }

    static func samplePDF(pages: Int = 3, dark: Bool = false) -> URL {
        let w = PDFWriter(title: "Sample")
        for i in 0..<pages {
            w.page(Paper.a4) { ctx in
                if dark { ctx.setFillColor(UIColor.black.cgColor); ctx.fill(CGRect(origin: .zero, size: Paper.a4)) }
                ctx.setStrokeColor(UIColor.fsTeal.cgColor); ctx.setLineWidth(2)
                ctx.stroke(CGRect(x: 60, y: 500, width: 200, height: 120))
                ctx.move(to: CGPoint(x: 60, y: 400)); ctx.addLine(to: CGPoint(x: 500, y: 420)); ctx.strokePath()
                ctx.setFillColor(UIColor.fsRed.cgColor); ctx.fillEllipse(in: CGRect(x: 350, y: 520, width: 90, height: 90))
                let col: UIColor = dark ? .white : .black
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: col]
                let body = "Page \(i + 1) — Penyata Akaun\nDate        Description           Amount\n01/10/2026  Gaji bulanan          5,200.00\n02/10/2026  Bayaran takaful         -310.50\nNo. IC: 900101-14-5678"
                Draw.text(body, in: CGRect(x: 60, y: 60, width: 480, height: 200), pageHeight: Paper.a4.height, ctx: ctx, attrs: attrs)
            }
        }
        let u = Workspace.unique(Workspace.newDir("Test"), dark ? "dark.pdf" : "sample.pdf")
        try? w.finish().write(to: u)
        return u
    }

    static func sampleImage() -> URL {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).image { c in
            UIColor(white: 0.85, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
            ("Scanned receipt\nJumlah RM 45.90" as NSString).draw(at: CGPoint(x: 80, y: 120),
                withAttributes: [.font: UIFont.systemFont(ofSize: 48, weight: .bold), .foregroundColor: UIColor.darkGray])
        }
        let u = Workspace.unique(Workspace.newDir("Test"), "photo.jpg")
        try? img.jpegData(compressionQuality: 0.9)?.write(to: u)
        return u
    }

    static func check(_ name: String, _ body: () throws -> String) {
        let t = Date()
        do {
            let info = try body()
            log("PASS \(name) — \(info) (\(String(format: "%.1f", Date().timeIntervalSince(t)))s)")
        } catch {
            log("FAIL \(name) — \(error.localizedDescription)")
        }
    }

    static func pdfInfo(_ u: URL) throws -> String {
        guard let d = PDFDocument(url: u) else { throw IQError.msg("output not a PDF", "") }
        return "\(d.pageCount)p \(Workspace.sizeString(u))\(d.isEncrypted ? " encrypted" : "")"
    }

    @MainActor
    static func run() async {
        log("START")
        log("DIR " + Workspace.root.path)
        let pdf = samplePDF()
        let dark = samplePDF(pages: 2, dark: true)
        let photo = sampleImage()
        let dir = Workspace.newDir("TestOut")
        func o(_ n: String) -> URL { Workspace.unique(dir, n) }

        check("merge") { let u = o("m.pdf"); try OrganizeEngine.merge([pdf, dark], out: u); return try pdfInfo(u) }
        check("split") { "\(try OrganizeEngine.split(pdf, mode: 1, ranges: "1-2, 3", every: 2, outDir: dir).count) files" }
        check("remove") { let u = o("r.pdf"); try OrganizeEngine.remove(pdf, indices: [1], out: u); return try pdfInfo(u) }
        check("reorder") { let u = o("re.pdf"); try OrganizeEngine.subset(pdf, indices: [2, 0, 1], out: u); return try pdfInfo(u) }
        check("rotate") { let u = o("rot.pdf"); try OrganizeEngine.rotate(pdf, angle: 90, range: "", out: u); return try pdfInfo(u) }
        let rotated = o("rotated.pdf"); try? OrganizeEngine.rotate(pdf, angle: 90, range: "1", out: rotated)
        check("booklet") { let u = o("b.pdf"); try OrganizeEngine.booklet(pdf, out: u); return try pdfInfo(u) }
        check("nup") { let u = o("n.pdf"); try OrganizeEngine.nUp(pdf, perSheet: 4, border: true, out: u); return try pdfInfo(u) }
        check("compress") { let u = o("c.pdf"); let m = try OptimizeEngine.compress(pdf, level: 1, targetKB: nil, out: u, progress: nil); return try pdfInfo(u) + " " + m }
        check("compress-target") { let u = o("c2.pdf"); let m = try OptimizeEngine.compress(pdf, level: 1, targetKB: 100, out: u, progress: nil); return m }
        check("crop") { let u = o("crop.pdf"); try OptimizeEngine.crop(rotated, insets: .init(top: 0.1, bottom: 0.1, left: 0.1, right: 0.1), range: "", out: u); return try pdfInfo(u) }
        check("grayscale") { let u = o("g.pdf"); try OptimizeEngine.grayscale(pdf, out: u, progress: nil); return try pdfInfo(u) }
        check("repair") { let u = o("rep.pdf"); return try OptimizeEngine.repair(pdf, out: u) }
        check("flatten") { let u = o("f.pdf"); try OptimizeEngine.flatten(pdf, out: u); return try pdfInfo(u) }
        check("pdfa") { let u = o("a.pdf"); try OptimizeEngine.pdfa(pdf, out: u, progress: nil); return try pdfInfo(u) }
        check("magic") { let u = o("mg.pdf"); try OptimizeEngine.magic([photo, pdf], mode: 0, out: u, progress: nil); return try pdfInfo(u) }
        check("inksaver") { let u = o("ink.pdf"); try OptimizeEngine.inkSaver(dark, mode: 0, grayscale: false, out: u, progress: nil); return try pdfInfo(u) }
        check("thesis") { let u = o("th.pdf"); try OptimizeEngine.thesis(rotated, marginsCM: [3.8, 2.5, 2.5, 2.5], out: u); return try pdfInfo(u) }
        check("cornell") { let u = o("co.pdf"); try OptimizeEngine.cornell(pdf, perPage: 2, out: u); return try pdfInfo(u) }
        check("ocr") { let r = try OCREngine.run([photo], malay: true, outDir: dir, progress: nil); return "\(r.chars) chars: " + ((try? String(contentsOf: r.txt)) ?? "").replacingOccurrences(of: "\n", with: " | ") }
        check("jpg2pdf") { let u = o("j.pdf"); try ConvertEngine.imagesToPDF([photo], pageSize: 0, orientation: 0, margin: 20, out: u, progress: nil); return try pdfInfo(u) }
        check("pdf2jpg") { "\(try ConvertEngine.pdfToImages(pdf, png: false, dpi: 100, quality: 0.8, transparent: false, range: "", outDir: dir, progress: nil).count) images" }
        check("pdf2png") { "\(try ConvertEngine.pdfToImages(pdf, png: true, dpi: 100, quality: 1, transparent: true, range: "1", outDir: dir, progress: nil).count) images" }
        check("pdf2text") { let u = o("t.txt"); return String(try ConvertEngine.pdfToText(pdf, out: u).prefix(60)).replacingOccurrences(of: "\n", with: " | ") }
        let docx = o("w.docx")
        check("pdf2word") { try ConvertEngine.pdfToWord(pdf, mode: 0, out: docx, progress: nil); return Workspace.sizeString(docx) }
        check("pdf2word-layout") { let u = o("w2.docx"); try ConvertEngine.pdfToWord(pdf, mode: 1, out: u, progress: nil); return Workspace.sizeString(u) }
        var xlsx: URL? = nil
        check("pdf2excel") {
            let r = try ConvertEngine.pdfToExcel(pdf, oneSheet: false, outDir: dir, progress: nil); xlsx = r.first
            return ((try? String(contentsOf: r[1])) ?? "").replacingOccurrences(of: "\n", with: " | ").prefix(160).description
        }
        let pptx = o("p.pptx")
        check("pdf2pptx") { try ConvertEngine.pdfToPPTX(pdf, out: pptx, progress: nil); return Workspace.sizeString(pptx) }
        check("pdf2dxf") { "\(try ConvertEngine.pdfToDXF(pdf, millimetres: true, outDir: dir, progress: nil).count) dxf" }
        check("extract-images") { "\(try ConvertEngine.extractImages(o("j2.pdf").deletingLastPathComponent().appendingPathComponent("j.pdf"), outDir: dir, progress: nil).count) images" }
        check("pagenumbers") { let u = o("pn.pdf"); try StampEngine.pageNumbers(rotated, position: 4, format: 1, start: 1, fontSize: 11, skipFirst: false, out: u); return try pdfInfo(u) }
        check("bates") { let u = o("bt.pdf"); try StampEngine.bates(pdf, prefix: "ABC", suffix: "", start: 1, digits: 6, position: 5, fontSize: 10, out: u); return try pdfInfo(u) }
        check("watermark") { let u = o("wm.pdf"); try StampEngine.watermark(pdf, text: "SULIT", style: 2, colorIndex: 1, opacity: 0.2, fontSize: 60, range: "", out: u); return try pdfInfo(u) }
        let locked = o("locked.pdf")
        check("protect") { try StampEngine.protect(pdf, password: "1234", out: locked); return try pdfInfo(locked) }
        check("unlock") { let u = o("un.pdf"); try StampEngine.unlock(locked, password: "1234", out: u); return try pdfInfo(u) }
        check("metadata") {
            let u = o("md.pdf"); try StampEngine.writeMetadata(pdf, fields: ["title": "Ujian", "author": "Fairuz", "keywords": "a, b"], out: u)
            return StampEngine.readMetadata(u).description
        }
        check("redact") {
            guard let d = PDFDocument(url: pdf) else { throw IQError.cannotOpen }
            var n = 0
            for sel in d.findString("900101", withOptions: [.caseInsensitive]) {
                for p in sel.pages {
                    let a = PDFAnnotation(bounds: sel.bounds(for: p), forType: .square, withProperties: nil)
                    a.userName = StampEngine.redactTag; a.interiorColor = .black; p.addAnnotation(a); n += 1
                }
            }
            let u = o("red.pdf"); try StampEngine.applyRedactions(d).write(to: u)
            let still = PDFDocument(url: u)?.string?.contains("900101") ?? false
            return "\(n) boxes, text remains: \(still)"
        }
        check("edit-flatten") {
            guard let d = PDFDocument(url: pdf), let p = d.page(at: 0) else { throw IQError.cannotOpen }
            let a = PDFAnnotation(bounds: CGRect(x: 100, y: 700, width: 200, height: 30), forType: .freeText, withProperties: nil)
            a.contents = "Hello"; a.font = .systemFont(ofSize: 14); p.addAnnotation(a)
            let ia = ImageAnnotation(bounds: CGRect(x: 300, y: 100, width: 120, height: 60), forType: .stamp, withProperties: nil)
            ia.image = UIImage(systemName: "signature"); p.addAnnotation(ia)
            let u = o("ed.pdf"); try OptimizeEngine.flatten(d).write(to: u)
            return try pdfInfo(u) + " has text: \(PDFDocument(url: u)?.string?.contains("Hello") ?? false)"
        }
        check("compare") { let u = o("cmp.pdf"); return try CompareEngine.compare(pdf, rotated, out: u, progress: nil) }
        check("zip") { let z = o("z.zip"); try ZipWriter.zip(files: [pdf, photo], to: z); let r = try ZipReader(data: try Data(contentsOf: z)); return "\(r.entries.count) entries" }

        // Office round trips
        do {
            let html = try OfficeImport.docxToHTML(try Data(contentsOf: docx))
            let data = try await WebPDF.render(html: html)
            try? data.write(to: o("rt_word.pdf"))
            log("PASS word2pdf(docx) — \(PDFDocument(data: data)?.pageCount ?? 0)p, text: \(PDFDocument(data: data)?.string?.prefix(40) ?? "")")
        } catch { log("FAIL word2pdf — \(error.localizedDescription)") }
        if let x = xlsx {
            do {
                let data = try await WebPDF.render(html: try OfficeImport.xlsxToHTML(try Data(contentsOf: x)), landscape: true)
                try? data.write(to: o("rt_excel.pdf"))
                log("PASS excel2pdf — \(PDFDocument(data: data)?.pageCount ?? 0)p")
            } catch { log("FAIL excel2pdf — \(error.localizedDescription)") }
        }
        do {
            let data = try PptxRenderer.render(try Data(contentsOf: pptx), progress: nil)
            try? data.write(to: o("rt_pptx.pdf"))
            log("PASS pptx2pdf — \(PDFDocument(data: data)?.pageCount ?? 0)p")
        } catch { log("FAIL pptx2pdf — \(error.localizedDescription)") }
        do {
            let md = "# Tajuk\n\nSome **bold** and *italic* text.\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\ncode\n```"
            let data = try await WebPDF.render(html: OfficeImport.markdownToHTML(md))
            try? data.write(to: o("rt_md.pdf"))
            log("PASS md2pdf — \(PDFDocument(data: data)?.pageCount ?? 0)p, text: \(PDFDocument(data: data)?.string?.prefix(30) ?? "")")
        } catch { log("FAIL md2pdf — \(error.localizedDescription)") }
        do {
            let t = Workspace.unique(dir, "n.txt"); try "Hello text file\nBaris dua".write(to: t, atomically: true, encoding: .utf8)
            let data = try OfficeImport.textToPDF(t)
            log("PASS txt2pdf — \(PDFDocument(data: data)?.pageCount ?? 0)p")
        } catch { log("FAIL txt2pdf — \(error.localizedDescription)") }
        // Office fixtures copied in by CI
        let fx = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fixtures")
        for f in (try? FileManager.default.contentsOfDirectory(at: fx, includingPropertiesForKeys: nil)) ?? [] {
            do {
                var data = Data()
                switch f.pathExtension.lowercased() {
                case "docx": data = try await WebPDF.render(html: try OfficeImport.docxToHTML(try Data(contentsOf: f)))
                case "xlsx": data = try await WebPDF.render(html: try OfficeImport.xlsxToHTML(try Data(contentsOf: f)), landscape: true, margin: 24)
                case "pptx": data = try PptxRenderer.render(try Data(contentsOf: f), progress: nil)
                default: continue
                }
                try data.write(to: o("fx_" + f.deletingPathExtension().lastPathComponent + "_" + f.pathExtension + ".pdf"))
                log("PASS fixture \(f.lastPathComponent) — \(PDFDocument(data: data)?.pageCount ?? 0)p")
            } catch { log("FAIL fixture \(f.lastPathComponent) — \(error.localizedDescription)") }
        }
        log("END")
        exit(0)
    }
}
