import UIKit

/// Draws .pptx slides (backgrounds, shapes, pictures, tables, text) into a PDF.
final class PptxRenderer {
    private let zip: ZipReader
    private var theme: [String: UIColor] = [:]
    private let emu: CGFloat = 12700 // EMU per point

    init(data: Data) throws {
        zip = try ZipReader(data: data)
    }

    static func render(_ data: Data, progress: Progress?) throws -> Data {
        let r = try PptxRenderer(data: data)
        return try r.render(progress: progress)
    }

    func render(progress: Progress?) throws -> Data {
        guard let pres = XParser.parse(zip["ppt/presentation.xml"]) else { throw IQError.cannotOpen }
        let rels = parseRels(zip["ppt/_rels/presentation.xml.rels"])
        var size = CGSize(width: 960, height: 540)
        if let sz = pres.first("p:sldSz"), let cx = Double(sz["cx"] ?? ""), let cy = Double(sz["cy"] ?? "") {
            size = CGSize(width: CGFloat(cx) / emu, height: CGFloat(cy) / emu)
        }
        let ids = pres.first("p:sldIdLst")?.all("p:sldId").compactMap { $0["r:id"] } ?? []
        let paths = ids.compactMap { rels[$0] }.map { resolvePath(base: "ppt/presentation.xml", target: $0) }
        guard !paths.isEmpty else { throw IQError.msg("No slides found.", "Tiada slaid ditemui.") }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            for (i, path) in paths.enumerated() {
                ctx.beginPage()
                autoreleasepool { drawSlide(path, size: size, ctx: ctx.cgContext) }
                progress?(Double(i + 1) / Double(paths.count))
            }
        }
    }

    // MARK: Slide

    private struct Part { let path: String; let root: XNode; let rels: [String: String] }

    private func part(_ path: String) -> Part? {
        guard let root = XParser.parse(zip[path]) else { return nil }
        return Part(path: path, root: root, rels: parseRels(zip[relsPath(for: path)]))
    }

    private func related(_ p: Part, typeSuffix: String) -> Part? {
        for r in parseRelTypes(zip[relsPath(for: p.path)]) where r.type.hasSuffix(typeSuffix) {
            return part(resolvePath(base: p.path, target: r.target))
        }
        return nil
    }

    private func drawSlide(_ path: String, size: CGSize, ctx: CGContext) {
        guard let slide = part(path) else { return }
        let layout = related(slide, typeSuffix: "/slideLayout")
        let master = layout.flatMap { related($0, typeSuffix: "/slideMaster") }
        if let m = master, let th = related(m, typeSuffix: "/theme") { loadTheme(th.root) }

        // Background
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        for p in [slide, layout, master].compactMap({ $0 }) {
            if let bg = p.root.first("p:bg") {
                drawBackground(bg, part: p, size: size)
                break
            }
        }

        let ctxInfo = Inherit(layout: layout, master: master)
        let showMaster = slide.root["showMasterSp"] != "0"
        if showMaster, let m = master, let tree = m.root.first("p:spTree") { drawTree(tree, part: m, ctx: ctx, inherit: nil, skipPlaceholders: true) }
        if showMaster, let l = layout, let tree = l.root.first("p:spTree") { drawTree(tree, part: l, ctx: ctx, inherit: nil, skipPlaceholders: true) }
        if let tree = slide.root.first("p:spTree") { drawTree(tree, part: slide, ctx: ctx, inherit: ctxInfo, skipPlaceholders: false) }
    }

    private struct Inherit { let layout: Part?; let master: Part? }

    private func drawBackground(_ bg: XNode, part: Part, size: CGSize) {
        let full = CGRect(origin: .zero, size: size)
        if let pr = bg.child("p:bgPr") {
            if let blip = pr.first("a:blip"), let id = blip["r:embed"], let t = part.rels[id],
               let d = zip[resolvePath(base: part.path, target: t)], let img = UIImage(data: d) {
                img.draw(in: full); return
            }
            if let c = fillColor(pr) { c.setFill(); UIRectFill(full) }
        } else if let ref = bg.child("p:bgRef"), let c = color(in: ref) {
            c.setFill(); UIRectFill(full)
        }
    }

    // MARK: Shapes

    private typealias Mapper = (CGRect) -> CGRect

    private func drawTree(_ tree: XNode, part: Part, ctx: CGContext, inherit: Inherit?, skipPlaceholders: Bool, map: Mapper? = nil) {
        for el in tree.children {
            switch el.name {
            case "p:sp", "p:cxnSp":
                let ph = el.first("p:ph")
                if skipPlaceholders && ph != nil { continue }
                drawShape(el, part: part, ctx: ctx, inherit: inherit, map: map)
            case "p:pic":
                drawPicture(el, part: part, map: map)
            case "p:graphicFrame":
                drawTable(el, map: map)
            case "p:grpSp":
                guard let x = el.child("p:grpSpPr")?.child("a:xfrm"), let off = x.child("a:off"), let ext = x.child("a:ext") else {
                    drawTree(el, part: part, ctx: ctx, inherit: inherit, skipPlaceholders: skipPlaceholders, map: map); continue
                }
                let chOff = x.child("a:chOff") ?? off, chExt = x.child("a:chExt") ?? ext
                let o = point(off), e = sizeOf(ext), co = point(chOff), ce = sizeOf(chExt)
                let sx = ce.width > 0 ? e.width / ce.width : 1, sy = ce.height > 0 ? e.height / ce.height : 1
                let inner: Mapper = { r in
                    let m = CGRect(x: o.x + (r.minX - co.x) * sx, y: o.y + (r.minY - co.y) * sy, width: r.width * sx, height: r.height * sy)
                    return map?(m) ?? m
                }
                drawTree(el, part: part, ctx: ctx, inherit: inherit, skipPlaceholders: skipPlaceholders, map: inner)
            default: break
            }
        }
    }

    private func point(_ n: XNode) -> CGPoint { CGPoint(x: CGFloat(Double(n["x"] ?? "0") ?? 0) / emu, y: CGFloat(Double(n["y"] ?? "0") ?? 0) / emu) }
    private func sizeOf(_ n: XNode) -> CGSize { CGSize(width: CGFloat(Double(n["cx"] ?? "0") ?? 0) / emu, height: CGFloat(Double(n["cy"] ?? "0") ?? 0) / emu) }

    private func frame(_ xfrm: XNode?) -> CGRect? {
        guard let x = xfrm, let off = x.child("a:off"), let ext = x.child("a:ext") else { return nil }
        return CGRect(origin: point(off), size: sizeOf(ext))
    }

    private func placeholderNode(_ ph: XNode, in part: Part?) -> XNode? {
        guard let p = part else { return nil }
        let type = ph["type"] ?? "body"
        let idx = ph["idx"]
        let shapes = p.root.descendants("p:sp")
        if let i = idx, let s = shapes.first(where: { $0.first("p:ph")?["idx"] == i }) { return s }
        let alias: [String: String] = ["ctrTitle": "title", "subTitle": "body", "obj": "body"]
        let t = alias[type] ?? type
        return shapes.first(where: { (alias[$0.first("p:ph")?["type"] ?? "body"] ?? ($0.first("p:ph")?["type"] ?? "body")) == t })
    }

    private func drawShape(_ sp: XNode, part: Part, ctx: CGContext, inherit: Inherit?, map: Mapper?) {
        let spPr = sp.child("p:spPr")
        var rect = frame(spPr?.child("a:xfrm"))
        let ph = sp.first("p:ph")
        var phLayout: XNode? = nil, phMaster: XNode? = nil
        if let ph = ph, let inh = inherit {
            phLayout = placeholderNode(ph, in: inh.layout)
            phMaster = placeholderNode(ph, in: inh.master)
            if rect == nil { rect = frame(phLayout?.child("p:spPr")?.child("a:xfrm")) ?? frame(phMaster?.child("p:spPr")?.child("a:xfrm")) }
        }
        guard var r = rect else { return }
        if let m = map { r = m(r) }

        let xfrm = spPr?.child("a:xfrm")
        let rot = CGFloat(Double(xfrm?["rot"] ?? "0") ?? 0) / 60000
        ctx.saveGState()
        if rot != 0 {
            ctx.translateBy(x: r.midX, y: r.midY)
            ctx.rotate(by: rot * .pi / 180)
            ctx.translateBy(x: -r.midX, y: -r.midY)
        }

        let geom = spPr?.child("a:prstGeom")?["prst"] ?? "rect"
        let path = shapePath(geom, r, isLine: sp.name == "p:cxnSp")
        // fill
        let style = sp.child("p:style")
        var fill: UIColor? = nil
        if let s = spPr {
            if s.child("a:noFill") != nil { fill = nil }
            else if let c = fillColor(s) { fill = c }
            else if s.child("a:solidFill") == nil, s.child("a:gradFill") == nil, let fr = style?.child("a:fillRef"), (fr["idx"] ?? "0") != "0" { fill = color(in: fr) }
        }
        if let f = fill, sp.name != "p:cxnSp" { f.setFill(); path.fill() }
        // outline
        var lineColor: UIColor? = nil
        var lineW: CGFloat = 0.75
        if let ln = spPr?.child("a:ln") {
            if ln.child("a:noFill") == nil { lineColor = fillColor(ln) ?? (style?.child("a:lnRef").flatMap { color(in: $0) }) }
            if let w = Double(ln["w"] ?? "") { lineW = max(0.25, CGFloat(w) / emu) }
        } else if let lr = style?.child("a:lnRef"), (lr["idx"] ?? "0") != "0" {
            lineColor = color(in: lr)
        }
        if let lc = lineColor { lc.setStroke(); path.lineWidth = lineW; path.stroke() }

        // text
        if let tx = sp.child("p:txBody") {
            drawText(tx, in: r, ph: ph, phNodes: [phLayout, phMaster].compactMap { $0 }, style: style)
        }
        ctx.restoreGState()
    }

    private func shapePath(_ geom: String, _ r: CGRect, isLine: Bool) -> UIBezierPath {
        if isLine || geom == "line" || geom.hasPrefix("straightConnector") || geom.hasPrefix("bentConnector") {
            let p = UIBezierPath(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); return p
        }
        switch geom {
        case "ellipse": return UIBezierPath(ovalIn: r)
        case "roundRect": return UIBezierPath(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.16)
        case "triangle":
            let p = UIBezierPath()
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.close()
            return p
        case "rightArrow":
            let p = UIBezierPath(); let hw = r.height * 0.5, sh = r.height * 0.25
            p.move(to: CGPoint(x: r.minX, y: r.minY + sh)); p.addLine(to: CGPoint(x: r.maxX - hw, y: r.minY + sh))
            p.addLine(to: CGPoint(x: r.maxX - hw, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - hw, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - hw, y: r.maxY - sh))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - sh)); p.close()
            return p
        default: return UIBezierPath(rect: r)
        }
    }

    // MARK: Text

    private func drawText(_ tx: XNode, in r: CGRect, ph: XNode?, phNodes: [XNode], style: XNode?) {
        let body = tx.child("a:bodyPr")
        let inheritedBody = phNodes.compactMap { $0.first("a:bodyPr") }.first
        func ins(_ key: String, _ def: Double) -> CGFloat {
            CGFloat(Double(body?[key] ?? inheritedBody?[key] ?? "") ?? def) / emu
        }
        let box = CGRect(x: r.minX + ins("lIns", 91440), y: r.minY + ins("tIns", 45720),
                         width: r.width - ins("lIns", 91440) - ins("rIns", 91440),
                         height: r.height - ins("tIns", 45720) - ins("bIns", 45720))
        guard box.width > 2 else { return }
        let phType = ph?["type"] ?? (ph != nil ? "body" : "")
        let isTitle = phType == "title" || phType == "ctrTitle"
        let anchor = body?["anchor"] ?? inheritedBody?["anchor"] ?? (isTitle ? "ctr" : "t")
        var scale: CGFloat = 1
        if let fs = body?.child("a:normAutofit")?["fontScale"], let v = Double(fs) { scale = CGFloat(v) / 100000 }

        let defaultColor = style?.child("a:fontRef").flatMap { color(in: $0) } ?? theme["tx1"] ?? .black
        let result = NSMutableAttributedString()
        let paras = tx.all("a:p")
        for (pi, p) in paras.enumerated() {
            let ppr = p.child("a:pPr")
            let lvl = Int(ppr?["lvl"] ?? "0") ?? 0
            let para = NSMutableParagraphStyle()
            switch ppr?["algn"] ?? (phType == "ctrTitle" || phType == "subTitle" ? "ctr" : "l") {
            case "ctr": para.alignment = .center
            case "r": para.alignment = .right
            case "just", "dist": para.alignment = .justified
            default: para.alignment = .left
            }
            para.paragraphSpacing = 4
            let baseSize: CGFloat = isTitle ? 40 : (phType == "body" || phType == "obj" || phType.isEmpty && ph != nil ? max(14, 26 - CGFloat(lvl) * 3) : 18)
            var bullet = ""
            let isBodyPh = ph != nil && !isTitle && phType != "subTitle" && phType != "sldNum" && phType != "dt" && phType != "ftr"
            if ppr?.child("a:buNone") == nil {
                if let ch = ppr?.child("a:buChar")?["char"] { bullet = ch + "  " }
                else if ppr?.child("a:buAutoNum") != nil { bullet = "\(pi + 1).  " }
                else if isBodyPh { bullet = "•  " }
            }
            para.headIndent = CGFloat(lvl) * 22 + (bullet.isEmpty ? 0 : 16)
            para.firstLineHeadIndent = CGFloat(lvl) * 22

            var runsAdded = false
            var firstSize = baseSize
            for c in p.children where c.name == "a:r" || c.name == "a:br" || c.name == "a:fld" {
                if c.name == "a:br" { result.append(NSAttributedString(string: "\u{2028}")); continue }
                let rpr = c.child("a:rPr")
                let endRpr = p.child("a:endParaRPr")
                var size = baseSize
                if let sz = rpr?["sz"], let v = Double(sz) { size = CGFloat(v) / 100 }
                else if let sz = endRpr?["sz"], let v = Double(sz) { size = CGFloat(v) / 100 }
                size *= scale
                if !runsAdded { firstSize = size }
                let bold = rpr?["b"] == "1"
                let italic = rpr?["i"] == "1"
                var font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
                if let face = rpr?.child("a:latin")?["typeface"], !face.hasPrefix("+"), let f = UIFont(name: face, size: size) { font = f }
                if italic, let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: d, size: size) }
                if bold, let d = font.fontDescriptor.withSymbolicTraits(.traitBold) { font = UIFont(descriptor: d, size: size) }
                let col = rpr.flatMap { fillColor($0) } ?? defaultColor
                var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col, .paragraphStyle: para]
                if rpr?["u"] != nil && rpr?["u"] != "none" { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                let text = c.child("a:t")?.text ?? ""
                if !runsAdded && !bullet.isEmpty {
                    result.append(NSAttributedString(string: bullet, attributes: attrs))
                }
                result.append(NSAttributedString(string: text, attributes: attrs))
                runsAdded = true
            }
            if !runsAdded {
                let f = UIFont.systemFont(ofSize: firstSize * scale * 0.6)
                result.append(NSAttributedString(string: " ", attributes: [.font: f, .paragraphStyle: para]))
            }
            if pi < paras.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        guard result.length > 0 else { return }

        // shrink to fit the box
        var attr: NSAttributedString = result
        var bounds = attr.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        var tries = 0
        while bounds.height > box.height * 1.02 && tries < 8 {
            let m = NSMutableAttributedString(attributedString: attr)
            m.enumerateAttribute(.font, in: NSRange(location: 0, length: m.length)) { v, range, _ in
                if let f = v as? UIFont { m.addAttribute(.font, value: f.withSize(f.pointSize * 0.9), range: range) }
            }
            attr = m
            bounds = attr.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            tries += 1
        }
        var y = box.minY
        if anchor == "ctr" { y = box.midY - bounds.height / 2 } else if anchor == "b" { y = box.maxY - bounds.height }
        attr.draw(with: CGRect(x: box.minX, y: y, width: box.width, height: max(bounds.height, box.height)),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    // MARK: Pictures & tables

    private func drawPicture(_ pic: XNode, part: Part, map: Mapper?) {
        guard var r = frame(pic.child("p:spPr")?.child("a:xfrm")) else { return }
        if let m = map { r = m(r) }
        guard let blip = pic.first("a:blip"), let id = blip["r:embed"], let t = part.rels[id],
              let d = zip[resolvePath(base: part.path, target: t)] else { return }
        if let img = UIImage(data: d) {
            img.draw(in: r)
        } else {
            UIColor(white: 0.92, alpha: 1).setFill(); UIRectFill(r)
        }
    }

    private func drawTable(_ gf: XNode, map: Mapper?) {
        guard let tbl = gf.first("a:tbl"), var r = frame(gf.child("p:xfrm")) else { return }
        if let m = map { r = m(r) }
        let cols = tbl.child("a:tblGrid")?.all("a:gridCol").map { CGFloat(Double($0["w"] ?? "0") ?? 0) / emu } ?? []
        guard !cols.isEmpty else { return }
        let total = cols.reduce(0, +)
        let k = total > 0 ? r.width / total : 1
        var y = r.minY
        for (ri, tr) in tbl.all("a:tr").enumerated() {
            let h = max(14, CGFloat(Double(tr["h"] ?? "0") ?? 0) / emu)
            var x = r.minX
            for (ci, tc) in tr.all("a:tc").enumerated() where ci < cols.count {
                let span = Int(tc["gridSpan"] ?? "1") ?? 1
                var w: CGFloat = 0
                for s in ci..<min(cols.count, ci + span) { w += cols[s] * k }
                let cell = CGRect(x: x, y: y, width: w, height: h)
                let fill = tc.child("a:tcPr").flatMap { fillColor($0) } ?? (ri == 0 ? (theme["accent1"] ?? .fsTeal) : UIColor(white: ri % 2 == 0 ? 0.95 : 0.9, alpha: 1))
                fill.setFill(); UIRectFill(cell)
                UIColor.white.setStroke()
                let b = UIBezierPath(rect: cell); b.lineWidth = 1; b.stroke()
                let text = tc.descendants("a:p").map { $0.descendants("a:t").map { $0.text }.joined() }.joined(separator: "\n")
                let sz = tc.descendants("a:rPr").first.flatMap { Double($0["sz"] ?? "") }.map { CGFloat($0) / 100 } ?? 14
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: sz, weight: ri == 0 ? .semibold : .regular),
                                                            .foregroundColor: ri == 0 ? UIColor.white : UIColor.black]
                (text as NSString).draw(in: cell.insetBy(dx: 5, dy: 3), withAttributes: attrs)
                x += w
            }
            y += h
        }
    }

    // MARK: Colours

    private func loadTheme(_ root: XNode) {
        guard theme.isEmpty, let cs = root.first("a:clrScheme") else { return }
        for c in cs.children {
            let key = c.name.replacingOccurrences(of: "a:", with: "")
            if let v = c.child("a:srgbClr")?["val"] { theme[key] = UIColor(hex: v) }
            else if let v = c.child("a:sysClr")?["lastClr"] { theme[key] = UIColor(hex: v) }
        }
        theme["tx1"] = theme["dk1"]; theme["bg1"] = theme["lt1"]; theme["tx2"] = theme["dk2"]; theme["bg2"] = theme["lt2"]
    }

    private func fillColor(_ n: XNode) -> UIColor? {
        if let s = n.child("a:solidFill") { return color(in: s) }
        if let g = n.child("a:gradFill"), let stop = g.first("a:gs") { return color(in: stop) }
        return nil
    }

    private func color(in n: XNode) -> UIColor? {
        for c in n.children {
            var base: UIColor? = nil
            switch c.name {
            case "a:srgbClr": base = UIColor(hex: c["val"] ?? "")
            case "a:schemeClr": base = theme[c["val"] ?? ""] ?? (c["val"] == "bg1" || c["val"] == "lt1" ? .white : .black)
            case "a:sysClr": base = UIColor(hex: c["lastClr"] ?? "000000")
            case "a:prstClr": base = c["val"] == "white" ? .white : .black
            default: continue
            }
            guard var col = base else { continue }
            var lumMod: CGFloat = 1, lumOff: CGFloat = 0, alpha: CGFloat = 1
            for m in c.children {
                let v = CGFloat(Double(m["val"] ?? "") ?? 100000) / 100000
                switch m.name {
                case "a:lumMod": lumMod = v
                case "a:lumOff": lumOff = v
                case "a:alpha": alpha = v
                case "a:tint": col = col.mixed(with: .white, amount: 1 - v)
                case "a:shade": col = col.mixed(with: .black, amount: 1 - v)
                default: break
                }
            }
            if lumMod != 1 || lumOff != 0 { col = col.adjustedLuminance(mod: lumMod, off: lumOff) }
            return col.withAlphaComponent(alpha)
        }
        return nil
    }
}

extension UIColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1)
    }

    func adjustedLuminance(mod: CGFloat, off: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let mx = max(r, g, b), mn = min(r, g, b)
        var h: CGFloat = 0, s: CGFloat = 0
        var l = (mx + mn) / 2
        let d = mx - mn
        if d > 0 {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
        }
        l = max(0, min(1, l * mod + off))
        func hue(_ p: CGFloat, _ q: CGFloat, _ tt: CGFloat) -> CGFloat {
            var t = tt
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        if s == 0 { return UIColor(red: l, green: l, blue: l, alpha: a) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return UIColor(red: hue(p, q, h + 1 / 3), green: hue(p, q, h), blue: hue(p, q, h - 1 / 3), alpha: a)
    }
}
