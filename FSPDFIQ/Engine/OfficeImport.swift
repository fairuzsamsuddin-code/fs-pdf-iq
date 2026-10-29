import UIKit

/// Converts Office / text formats into HTML (rendered by WebPDF) or straight to PDF.
enum OfficeImport {

    static let baseCSS = """
    <style>
    @page { margin: 0; }
    body { font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 11pt; line-height: 1.45; color: #111; margin: 0; }
    h1 { font-size: 20pt; margin: 14pt 0 8pt; } h2 { font-size: 16pt; margin: 12pt 0 6pt; } h3 { font-size: 13pt; margin: 10pt 0 4pt; }
    h4, h5, h6 { font-size: 11.5pt; margin: 8pt 0 4pt; }
    p { margin: 0 0 6pt; }
    table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; page-break-inside: auto; }
    tr { page-break-inside: avoid; }
    td, th { border: 0.6pt solid #9aa0a6; padding: 3pt 5pt; vertical-align: top; font-size: 10pt; }
    th { background: #eef4f4; font-weight: 600; }
    img { max-width: 100%; height: auto; }
    pre { background: #f5f6f7; border-radius: 6px; padding: 8pt; white-space: pre-wrap; font-size: 9.5pt; font-family: Menlo, Courier, monospace; }
    code { font-family: Menlo, Courier, monospace; font-size: 9.5pt; background: #f2f3f4; padding: 0 2pt; border-radius: 3px; }
    blockquote { border-left: 3pt solid #008183; margin: 6pt 0; padding: 2pt 10pt; color: #444; }
    .pb { page-break-after: always; }
    .sheet { font-size: 13pt; color: #008183; margin: 0 0 6pt; }
    .li { margin-left: 14pt; text-indent: -10pt; }
    hr { border: 0; border-top: 0.8pt solid #ccc; margin: 10pt 0; }
    </style>
    """

    static func wrap(_ body: String) -> String {
        "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width'>\(baseCSS)</head><body>\(body)</body></html>"
    }

    // MARK: Word (.docx)

    static func docxToHTML(_ data: Data) throws -> String {
        let zip = try ZipReader(data: data)
        guard let root = XParser.parse(zip["word/document.xml"]), let body = root.first("w:body") else { throw IQError.cannotOpen }
        let rels = parseRels(zip["word/_rels/document.xml.rels"])
        var html = ""

        func isOn(_ n: XNode?) -> Bool {
            guard let n = n else { return false }
            let v = n["w:val"] ?? "true"
            return v != "0" && v != "false" && v != "none"
        }

        func run(_ r: XNode) -> String {
            let rpr = r.child("w:rPr")
            var style = ""
            if let sz = rpr?.child("w:sz")?["w:val"], let half = Double(sz) { style += "font-size:\(half / 2)pt;" }
            if let c = rpr?.child("w:color")?["w:val"], c.count == 6 { style += "color:#\(c);" }
            if let h = rpr?.child("w:highlight")?["w:val"], h != "none" { style += "background:\(h);" }
            var inner = ""
            for c in r.children {
                switch c.name {
                case "w:t": inner += c.text.htmlEscaped
                case "w:tab": inner += "&emsp;"
                case "w:br": inner += (c["w:type"] == "page") ? "</p><div class='pb'></div><p>" : "<br>"
                case "w:cr": inner += "<br>"
                case "w:drawing", "w:pict":
                    if let blip = c.first("a:blip"), let id = blip["r:embed"], let target = rels[id],
                       let img = zip[resolvePath(base: "word/document.xml", target: target)] {
                        let ext = (target as NSString).pathExtension.lowercased()
                        let mime = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
                        var dim = ""
                        if let e = c.first("wp:extent"), let cx = Double(e["cx"] ?? ""), let cy = Double(e["cy"] ?? "") {
                            dim = " style='width:\(Int(cx / 9525))px;height:\(Int(cy / 9525))px'"
                        }
                        inner += "<img src='data:\(mime);base64,\(img.base64EncodedString())'\(dim)>"
                    }
                default: break
                }
            }
            if inner.isEmpty { return "" }
            if isOn(rpr?.child("w:b")) { inner = "<b>\(inner)</b>" }
            if isOn(rpr?.child("w:i")) { inner = "<i>\(inner)</i>" }
            if isOn(rpr?.child("w:u")) { inner = "<u>\(inner)</u>" }
            if isOn(rpr?.child("w:strike")) { inner = "<s>\(inner)</s>" }
            if let va = rpr?.child("w:vertAlign")?["w:val"] {
                if va == "superscript" { inner = "<sup>\(inner)</sup>" } else if va == "subscript" { inner = "<sub>\(inner)</sub>" }
            }
            return style.isEmpty ? inner : "<span style='\(style)'>\(inner)</span>"
        }

        func runs(_ n: XNode) -> String {
            var s = ""
            for c in n.children {
                switch c.name {
                case "w:r": s += run(c)
                case "w:hyperlink", "w:ins", "w:smartTag", "w:sdt", "w:sdtContent", "w:fldSimple": s += runs(c)
                default: break
                }
            }
            return s
        }

        func paragraph(_ p: XNode) -> String {
            let ppr = p.child("w:pPr")
            let style = (ppr?.child("w:pStyle")?["w:val"] ?? "").lowercased()
            var tag = "p"
            if style == "title" { tag = "h1" }
            else if style.hasPrefix("heading") || style.hasPrefix("kepala") {
                let digits = style.filter { $0.isNumber }
                tag = "h" + String(min(6, max(1, Int(digits) ?? 2)))
            }
            var css = ""
            if let jc = ppr?.child("w:jc")?["w:val"] {
                let map = ["center": "center", "right": "right", "end": "right", "both": "justify", "distribute": "justify"]
                if let a = map[jc] { css += "text-align:\(a);" }
            }
            var inner = runs(p)
            if let num = ppr?.child("w:numPr") {
                let lvl = Int(num.child("w:ilvl")?["w:val"] ?? "0") ?? 0
                css += "margin-left:\(14 + lvl * 16)pt;text-indent:-10pt;"
                inner = "•&nbsp;&nbsp;" + inner
            }
            if inner.isEmpty { inner = "&nbsp;" }
            return "<\(tag)\(css.isEmpty ? "" : " style='\(css)'")>\(inner)</\(tag)>"
        }

        func table(_ t: XNode) -> String {
            var s = "<table>"
            for tr in t.all("w:tr") {
                s += "<tr>"
                for tc in tr.all("w:tc") {
                    let span = tc.child("w:tcPr")?.child("w:gridSpan")?["w:val"] ?? "1"
                    var shade = ""
                    if let fill = tc.child("w:tcPr")?.child("w:shd")?["w:fill"], fill.count == 6 { shade = " style='background:#\(fill)'" }
                    s += "<td colspan='\(span)'\(shade)>"
                    for c in tc.children {
                        if c.name == "w:p" { s += paragraph(c) } else if c.name == "w:tbl" { s += table(c) }
                    }
                    s += "</td>"
                }
                s += "</tr>"
            }
            return s + "</table>"
        }

        for el in body.children {
            switch el.name {
            case "w:p": html += paragraph(el)
            case "w:tbl": html += table(el)
            case "w:sdt":
                for c in el.child("w:sdtContent")?.children ?? [] {
                    if c.name == "w:p" { html += paragraph(c) } else if c.name == "w:tbl" { html += table(c) }
                }
            default: break
            }
        }
        return wrap(html)
    }

    // MARK: Excel (.xlsx / .csv)

    static func xlsxToHTML(_ data: Data) throws -> String {
        let zip = try ZipReader(data: data)
        guard let wb = XParser.parse(zip["xl/workbook.xml"]) else { throw IQError.cannotOpen }
        let rels = parseRels(zip["xl/_rels/workbook.xml.rels"])
        var shared: [String] = []
        if let sst = XParser.parse(zip["xl/sharedStrings.xml"]) {
            shared = sst.all("si").map { si in si.descendants("t").map { $0.text }.joined() }
        }
        var html = ""
        let sheets = wb.first("sheets")?.all("sheet") ?? []
        for (si, sheet) in sheets.enumerated() {
            guard let rid = sheet["r:id"], let target = rels[rid],
                  let ws = XParser.parse(zip[resolvePath(base: "xl/workbook.xml", target: target)]) else { continue }
            var grid: [Int: [Int: String]] = [:]
            var maxR = 0, maxC = 0
            for row in ws.first("sheetData")?.all("row") ?? [] {
                for c in row.all("c") {
                    guard let ref = c["r"] else { continue }
                    let (col, r) = cellIndex(ref)
                    guard r < 3000, col < 80 else { continue }
                    var v = c.child("v")?.text ?? ""
                    switch c["t"] ?? "" {
                    case "s": v = Int(v).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
                    case "inlineStr": v = c.child("is")?.descendants("t").map { $0.text }.joined() ?? ""
                    case "b": v = v == "1" ? "TRUE" : "FALSE"
                    case "str", "e": break
                    default: v = prettyNumber(v)
                    }
                    if v.isEmpty { continue }
                    grid[r, default: [:]][col] = v
                    maxR = max(maxR, r); maxC = max(maxC, col)
                }
            }
            if grid.isEmpty { continue }
            if si > 0 && !html.isEmpty { html += "<div class='pb'></div>" }
            html += "<div class='sheet'>\((sheet["name"] ?? "Sheet").htmlEscaped)</div><table>"
            for r in 0...maxR {
                html += "<tr>"
                for c in 0...maxC {
                    let v = grid[r]?[c] ?? ""
                    let numeric = Double(v.replacingOccurrences(of: ",", with: "")) != nil
                    html += r == 0 ? "<th>\(v.htmlEscaped)</th>" : "<td\(numeric ? " style='text-align:right'" : "")>\(v.htmlEscaped)</td>"
                }
                html += "</tr>"
            }
            html += "</table>"
        }
        if html.isEmpty { throw IQError.msg("This workbook has no data.", "Buku kerja ini tiada data.") }
        return wrap(html)
    }

    static func cellIndex(_ ref: String) -> (col: Int, row: Int) {
        var col = 0
        var digits = ""
        for ch in ref.uppercased() {
            if let a = ch.asciiValue, a >= 65, a <= 90 { col = col * 26 + Int(a - 64) } else if ch.isNumber { digits.append(ch) }
        }
        return (max(0, col - 1), max(0, (Int(digits) ?? 1) - 1))
    }

    static func prettyNumber(_ v: String) -> String {
        guard let d = Double(v) else { return v }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        f.minimumIntegerDigits = 1
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: d)) ?? v
    }

    static func csvToHTML(_ text: String) -> String {
        let rows = parseCSV(text)
        var html = "<table>"
        for (i, r) in rows.enumerated() {
            html += "<tr>" + r.map { i == 0 ? "<th>\($0.htmlEscaped)</th>" : "<td>\($0.htmlEscaped)</td>" }.joined() + "</tr>"
        }
        return wrap(html + "</table>")
    }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let sep: Character = text.prefix(2000).filter { $0 == ";" }.count > text.prefix(2000).filter { $0 == "," }.count ? ";" : ","
        var it = Array(text)
        it.append("\n")
        var i = 0
        while i < it.count {
            let c = it[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" { inQuotes = true }
            else if c == sep { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" { row.append(field); field = ""; if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }; row = [] }
            else if c != "\r" { field.append(c) }
            i += 1
        }
        return rows
    }

    // MARK: Markdown

    static func inlineMD(_ s: String) -> String {
        var t = s.htmlEscaped
        let rules: [(String, String)] = [
            ("!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)", "<img alt='$1' src='$2'>"),
            ("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", "<a href='$2'>$1</a>"),
            ("`([^`]+)`", "<code>$1</code>"),
            ("\\*\\*([^*]+)\\*\\*", "<b>$1</b>"),
            ("__([^_]+)__", "<b>$1</b>"),
            ("(?<![*\\w])\\*([^*\\n]+)\\*(?!\\*)", "<i>$1</i>"),
            ("(?<![_\\w])_([^_\\n]+)_(?![_\\w])", "<i>$1</i>"),
            ("~~([^~]+)~~", "<s>$1</s>")
        ]
        for (p, r) in rules {
            t = t.replacingOccurrences(of: p, with: r, options: .regularExpression)
        }
        return t
    }

    static func markdownToHTML(_ md: String) -> String {
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html = ""
        var i = 0
        var para: [String] = []
        func flush() {
            if !para.isEmpty { html += "<p>" + para.map(inlineMD).joined(separator: " ") + "</p>"; para = [] }
        }
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                html += "<pre><code>" + code.joined(separator: "\n").htmlEscaped + "</code></pre>"
                i += 1
                continue
            }
            if line.isEmpty { flush(); i += 1; continue }
            if let m = line.range(of: "^#{1,6}\\s", options: .regularExpression) {
                flush()
                let level = line[m].filter { $0 == "#" }.count
                html += "<h\(level)>" + inlineMD(String(line[m.upperBound...])) + "</h\(level)>"
                i += 1; continue
            }
            if line.range(of: "^(-{3,}|\\*{3,}|_{3,})$", options: .regularExpression) != nil { flush(); html += "<hr>"; i += 1; continue }
            if line.hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                html += "<blockquote>" + inlineMD(q.joined(separator: " ")) + "</blockquote>"
                continue
            }
            if line.hasPrefix("|"), i + 1 < lines.count, lines[i + 1].range(of: "^\\s*\\|?\\s*:?-{2,}", options: .regularExpression) != nil {
                flush()
                func cells(_ l: String) -> [String] {
                    var t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("|") { t.removeFirst() }
                    if t.hasSuffix("|") { t.removeLast() }
                    return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                }
                html += "<table><tr>" + cells(line).map { "<th>\(inlineMD($0))</th>" }.joined() + "</tr>"
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    html += "<tr>" + cells(lines[i]).map { "<td>\(inlineMD($0))</td>" }.joined() + "</tr>"
                    i += 1
                }
                html += "</table>"
                continue
            }
            let ul = line.range(of: "^[-*+]\\s+", options: .regularExpression)
            let ol = line.range(of: "^[0-9]+[.)]\\s+", options: .regularExpression)
            if ul != nil || ol != nil {
                flush()
                let ordered = ol != nil
                html += ordered ? "<ol>" : "<ul>"
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    let r = ordered ? l.range(of: "^[0-9]+[.)]\\s+", options: .regularExpression) : l.range(of: "^[-*+]\\s+", options: .regularExpression)
                    guard let rr = r else { break }
                    var item = String(l[rr.upperBound...])
                    if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                    else if item.lowercased().hasPrefix("[x] ") { item = "☑ " + item.dropFirst(4) }
                    let indent = lines[i].prefix(while: { $0 == " " }).count / 2
                    html += "<li style='margin-left:\(indent * 14)pt'>" + inlineMD(item) + "</li>"
                    i += 1
                }
                html += ordered ? "</ol>" : "</ul>"
                continue
            }
            para.append(line)
            i += 1
        }
        flush()
        return wrap(html)
    }

    // MARK: RTF / TXT

    @MainActor
    static func textToPDF(_ url: URL) throws -> Data {
        let ext = url.pathExtension.lowercased()
        var attr: NSAttributedString
        if ext == "rtf" {
            attr = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } else {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
            attr = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black])
        }
        return WebPDF.renderText(attr)
    }
}
