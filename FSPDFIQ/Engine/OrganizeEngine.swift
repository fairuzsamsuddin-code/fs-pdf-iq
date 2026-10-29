import UIKit
import PDFKit

typealias Progress = (Double) -> Void

enum OrganizeEngine {
    static func copyPages(from doc: PDFDocument, indices: [Int], into out: PDFDocument) {
        for i in indices {
            if let p = doc.page(at: i)?.copy() as? PDFPage {
                out.insert(p, at: out.pageCount)
            }
        }
    }

    static func merge(_ urls: [URL], out: URL, progress: Progress? = nil) throws {
        guard urls.count >= 1 else { throw IQError.noInput }
        let result = PDFDocument()
        for (n, u) in urls.enumerated() {
            let d = try PDFIO.open(u)
            copyPages(from: d, indices: Array(0..<d.pageCount), into: result)
            progress?(Double(n + 1) / Double(urls.count))
        }
        guard result.pageCount > 0 else { throw IQError.noPages }
        try PDFIO.write(result, to: out)
    }

    /// mode 0 = every page, 1 = custom ranges (each comma group = one file), 2 = every N pages
    static func split(_ url: URL, mode: Int, ranges: String, every: Int, outDir: URL) throws -> [URL] {
        let doc = try PDFIO.open(url)
        let n = doc.pageCount
        let base = Workspace.base(url)
        var groups: [[Int]] = []
        switch mode {
        case 1:
            let g = PDFIO.parseGroups(ranges)
            guard !g.isEmpty else { throw IQError.badRange }
            for s in g { groups.append(try PDFIO.parseGroup(s, count: n)) }
        case 2:
            let k = max(1, every)
            var i = 0
            while i < n { groups.append(Array(i..<min(n, i + k))); i += k }
        default:
            groups = (0..<n).map { [$0] }
        }
        var outs: [URL] = []
        for g in groups {
            let d = PDFDocument()
            copyPages(from: doc, indices: g, into: d)
            let label = g.count == 1 ? "p\(g[0] + 1)" : "p\(g.first! + 1)-\(g.last! + 1)"
            let u = Workspace.unique(outDir, "\(base)_\(label).pdf")
            try PDFIO.write(d, to: u)
            outs.append(u)
        }
        return outs
    }

    static func subset(_ url: URL, indices: [Int], out: URL) throws {
        guard !indices.isEmpty else { throw IQError.noPages }
        let doc = try PDFIO.open(url)
        let d = PDFDocument()
        copyPages(from: doc, indices: indices, into: d)
        try PDFIO.write(d, to: out)
    }

    static func remove(_ url: URL, indices: Set<Int>, out: URL) throws {
        let doc = try PDFIO.open(url)
        let keep = (0..<doc.pageCount).filter { !indices.contains($0) }
        guard !keep.isEmpty else {
            throw IQError.msg("You can't remove every page.", "Anda tidak boleh membuang semua halaman.")
        }
        try subset(url, indices: keep, out: out)
    }

    static func rotate(_ url: URL, angle: Int, range: String, out: URL) throws {
        let doc = try PDFIO.open(url)
        let idx = try PDFIO.parseRange(range, count: doc.pageCount)
        for i in idx { if let p = doc.page(at: i) { p.rotation = (p.rotation + angle) % 360 } }
        try PDFIO.write(doc, to: out)
    }

    /// Saddle-stitch booklet: 2 pages per A4 landscape side, printed double-sided (flip on short edge).
    static func booklet(_ url: URL, out: URL) throws {
        let doc = try PDFIO.open(url)
        let n = doc.pageCount
        guard n > 0 else { throw IQError.noPages }
        let total = ((n + 3) / 4) * 4
        let sheet = CGSize(width: Paper.a4.height, height: Paper.a4.width)
        let w = PDFWriter(title: Workspace.base(url) + " booklet")
        for s in 0..<(total / 4) {
            let sides = [(total - 1 - 2 * s, 2 * s), (2 * s + 1, total - 2 - 2 * s)]
            for (left, right) in sides {
                w.page(sheet) { ctx in
                    for (slot, idx) in [left, right].enumerated() {
                        guard idx < n, let p = doc.page(at: idx) else { continue }
                        let r = CGRect(x: slot == 0 ? 0 : sheet.width / 2, y: 0, width: sheet.width / 2, height: sheet.height).insetBy(dx: 14, dy: 14)
                        Draw.page(p, in: r, ctx: ctx)
                    }
                }
            }
        }
        try w.finish().write(to: out)
    }

    static func nUp(_ url: URL, perSheet: Int, border: Bool, out: URL) throws {
        let doc = try PDFIO.open(url)
        let n = doc.pageCount
        guard n > 0 else { throw IQError.noPages }
        let (cols, rows, landscape): (Int, Int, Bool) = {
            switch perSheet {
            case 2: return (2, 1, true)
            case 6: return (2, 3, false)
            case 9: return (3, 3, false)
            case 16: return (4, 4, false)
            default: return (2, 2, false)
            }
        }()
        let size = landscape ? CGSize(width: Paper.a4.height, height: Paper.a4.width) : Paper.a4
        let margin: CGFloat = 18, gap: CGFloat = 10
        let cellW = (size.width - 2 * margin - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let cellH = (size.height - 2 * margin - CGFloat(rows - 1) * gap) / CGFloat(rows)
        let per = cols * rows
        let w = PDFWriter()
        var i = 0
        while i < n {
            w.page(size) { ctx in
                for k in 0..<per {
                    let idx = i + k
                    guard idx < n, let p = doc.page(at: idx) else { break }
                    let col = k % cols, row = k / cols
                    let x = margin + CGFloat(col) * (cellW + gap)
                    let y = size.height - margin - CGFloat(row + 1) * cellH - CGFloat(row) * gap
                    let used = Draw.page(p, in: CGRect(x: x, y: y, width: cellW, height: cellH), ctx: ctx)
                    if border {
                        ctx.setStrokeColor(UIColor(white: 0.55, alpha: 1).cgColor)
                        ctx.setLineWidth(0.6)
                        ctx.stroke(used)
                    }
                }
            }
            i += per
        }
        try w.finish().write(to: out)
    }
}
