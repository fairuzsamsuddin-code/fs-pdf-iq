import Foundation
import CoreGraphics

// MARK: - DOCX

struct DocxWriter {
    private var body = ""
    private var images: [(name: String, data: Data)] = []

    mutating func paragraph(_ text: String, bold: Bool = false, sizePt: Double? = nil, align: String? = nil) {
        var ppr = ""
        if let a = align { ppr = "<w:pPr><w:jc w:val=\"\(a)\"/></w:pPr>" }
        var rpr = ""
        if bold || sizePt != nil {
            rpr = "<w:rPr>" + (bold ? "<w:b/>" : "")
            if let s = sizePt { rpr += "<w:sz w:val=\"\(Int(s * 2))\"/><w:szCs w:val=\"\(Int(s * 2))\"/>" }
            rpr += "</w:rPr>"
        }
        if text.isEmpty {
            body += "<w:p>\(ppr)</w:p>"
            return
        }
        // keep manual line breaks inside a paragraph
        let lines = text.components(separatedBy: "\n")
        var runs = ""
        for (i, l) in lines.enumerated() {
            if i > 0 { runs += "<w:r>\(rpr)<w:br/></w:r>" }
            runs += "<w:r>\(rpr)<w:t xml:space=\"preserve\">\(l.xmlEscaped)</w:t></w:r>"
        }
        body += "<w:p>\(ppr)\(runs)</w:p>"
    }

    mutating func pageBreak() {
        body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
    }

    /// Inline picture. Size in points.
    mutating func image(jpeg: Data, widthPt: CGFloat, heightPt: CGFloat) {
        let idx = images.count + 1
        let name = "image\(idx).jpeg"
        images.append((name, jpeg))
        let cx = Int(widthPt * 12700), cy = Int(heightPt * 12700)
        body += """
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(idx)" name="Picture \(idx)"/>\
        <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic><pic:nvPicPr><pic:cNvPr id="\(idx)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="rIdImg\(idx)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
        </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    func build(marginTwips: Int = 1134) -> Data {
        let doc = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)\
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="\(marginTwips)" w:right="\(marginTwips)" w:bottom="\(marginTwips)" w:left="\(marginTwips)" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>\
        </w:body></w:document>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>\
        <w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-MY"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
        </w:styles>
        """
        var rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        for (i, img) in images.enumerated() {
            rels += "<Relationship Id=\"rIdImg\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(img.name)\"/>"
        }
        rels += "</Relationships>"
        let types = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Default Extension="jpeg" ContentType="image/jpeg"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        </Types>
        """
        let root = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        </Relationships>
        """
        var z = ZipWriter()
        z.add("[Content_Types].xml", Data(types.utf8))
        z.add("_rels/.rels", Data(root.utf8))
        z.add("word/document.xml", Data(doc.utf8))
        z.add("word/styles.xml", Data(styles.utf8))
        z.add("word/_rels/document.xml.rels", Data(rels.utf8))
        for img in images { z.add("word/media/\(img.name)", img.data, compress: false) }
        return z.finish()
    }
}

// MARK: - XLSX

struct XlsxWriter {
    struct Sheet { var name: String; var rows: [[String]] }
    var sheets: [Sheet] = []

    static func columnName(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func numeric(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count < 20 else { return nil }
        var cleaned = t.replacingOccurrences(of: ",", with: "")
        var negative = false
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") { negative = true; cleaned = String(cleaned.dropFirst().dropLast()) }
        if cleaned.hasSuffix("-") || cleaned.hasSuffix("DR") { negative = true; cleaned = cleaned.replacingOccurrences(of: "DR", with: "").replacingOccurrences(of: "-", with: "") }
        if cleaned.hasSuffix("CR") { cleaned = String(cleaned.dropLast(2)) }
        guard cleaned.range(of: "^-?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        // keep leading-zero codes (account numbers etc.) as text
        if cleaned.count > 1 && cleaned.hasPrefix("0") && !cleaned.hasPrefix("0.") { return nil }
        if cleaned.count > 15 { return nil }
        return negative ? "-" + cleaned : cleaned
    }

    func build() -> Data {
        var usedNames = Set<String>()
        var names: [String] = []
        for (i, s) in sheets.enumerated() {
            var n = s.name.replacingOccurrences(of: "[\\[\\]:*?/\\\\]", with: " ", options: .regularExpression)
            if n.isEmpty { n = "Sheet\(i + 1)" }
            n = String(n.prefix(28))
            var cand = n
            var k = 2
            while usedNames.contains(cand.lowercased()) { cand = "\(n) \(k)"; k += 1 }
            usedNames.insert(cand.lowercased())
            names.append(cand)
        }

        var types = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        for i in sheets.indices {
            types += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        types += "</Types>"

        let root = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """

        var wb = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>
        """
        var wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        """
        for i in sheets.indices {
            wb += "<sheet name=\"\(names[i].xmlEscaped)\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
            wbRels += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        wb += "</sheets></workbook>"
        wbRels += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"

        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
        <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>\
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
        </styleSheet>
        """

        var z = ZipWriter()
        z.add("[Content_Types].xml", Data(types.utf8))
        z.add("_rels/.rels", Data(root.utf8))
        z.add("xl/workbook.xml", Data(wb.utf8))
        z.add("xl/_rels/workbook.xml.rels", Data(wbRels.utf8))
        z.add("xl/styles.xml", Data(styles.utf8))

        for (i, sheet) in sheets.enumerated() {
            var maxCols = 0
            for r in sheet.rows { maxCols = max(maxCols, r.count) }
            var xml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            """
            if maxCols > 0 {
                xml += "<cols><col min=\"1\" max=\"\(maxCols)\" width=\"18\" customWidth=\"1\"/></cols>"
            }
            xml += "<sheetData>"
            for (ri, row) in sheet.rows.enumerated() {
                xml += "<row r=\"\(ri + 1)\">"
                for (ci, cell) in row.enumerated() where !cell.isEmpty {
                    let ref = XlsxWriter.columnName(ci) + "\(ri + 1)"
                    if let num = XlsxWriter.numeric(cell) {
                        xml += "<c r=\"\(ref)\"><v>\(num)</v></c>"
                    } else {
                        xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(cell.xmlEscaped)</t></is></c>"
                    }
                }
                xml += "</row>"
            }
            xml += "</sheetData></worksheet>"
            z.add("xl/worksheets/sheet\(i + 1).xml", Data(xml.utf8))
        }
        return z.finish()
    }
}

// MARK: - PPTX (one picture per slide)

struct PptxWriter {
    var slideSizeEMU: (cx: Int, cy: Int) = (12_192_000, 6_858_000)
    /// jpeg data + picture rect in EMU
    var slides: [(jpeg: Data, x: Int, y: Int, cx: Int, cy: Int)] = []

    private static let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
    private static let emptyTree = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
    private static let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let rt = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    func build() -> Data {
        let n = slides.count
        var types = PptxWriter.head + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Default Extension="jpeg" ContentType="image/jpeg"/>\
        <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>\
        <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>\
        <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>\
        <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        """
        for i in 0..<n {
            types += "<Override PartName=\"/ppt/slides/slide\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
        }
        types += "</Types>"

        let rootRels = PptxWriter.head + "<Relationships xmlns=\"\(PptxWriter.relNS)\"><Relationship Id=\"rId1\" Type=\"\(PptxWriter.rt)officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>"

        var pres = PptxWriter.head + "<p:presentation \(PptxWriter.ns) saveSubsetFonts=\"1\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:sldIdLst>"
        var presRels = PptxWriter.head + "<Relationships xmlns=\"\(PptxWriter.relNS)\"><Relationship Id=\"rId1\" Type=\"\(PptxWriter.rt)slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/><Relationship Id=\"rId2\" Type=\"\(PptxWriter.rt)theme\" Target=\"theme/theme1.xml\"/>"
        for i in 0..<n {
            pres += "<p:sldId id=\"\(256 + i)\" r:id=\"rId\(i + 3)\"/>"
            presRels += "<Relationship Id=\"rId\(i + 3)\" Type=\"\(PptxWriter.rt)slide\" Target=\"slides/slide\(i + 1).xml\"/>"
        }
        pres += "</p:sldIdLst><p:sldSz cx=\"\(slideSizeEMU.cx)\" cy=\"\(slideSizeEMU.cy)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/><p:defaultTextStyle/></p:presentation>"
        presRels += "</Relationships>"

        let master = PptxWriter.head + "<p:sldMaster \(PptxWriter.ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg><p:spTree>\(PptxWriter.emptyTree)</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>"
        let masterRels = PptxWriter.head + "<Relationships xmlns=\"\(PptxWriter.relNS)\"><Relationship Id=\"rId1\" Type=\"\(PptxWriter.rt)slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"\(PptxWriter.rt)theme\" Target=\"../theme/theme1.xml\"/></Relationships>"
        let layout = PptxWriter.head + "<p:sldLayout \(PptxWriter.ns) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>\(PptxWriter.emptyTree)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
        let layoutRels = PptxWriter.head + "<Relationships xmlns=\"\(PptxWriter.relNS)\"><Relationship Id=\"rId1\" Type=\"\(PptxWriter.rt)slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/></Relationships>"

        var z = ZipWriter()
        z.add("[Content_Types].xml", Data(types.utf8))
        z.add("_rels/.rels", Data(rootRels.utf8))
        z.add("ppt/presentation.xml", Data(pres.utf8))
        z.add("ppt/_rels/presentation.xml.rels", Data(presRels.utf8))
        z.add("ppt/slideMasters/slideMaster1.xml", Data(master.utf8))
        z.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", Data(masterRels.utf8))
        z.add("ppt/slideLayouts/slideLayout1.xml", Data(layout.utf8))
        z.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", Data(layoutRels.utf8))
        z.add("ppt/theme/theme1.xml", Data(PptxWriter.theme.utf8))

        for (i, s) in slides.enumerated() {
            let slide = PptxWriter.head + "<p:sld \(PptxWriter.ns)><p:cSld><p:spTree>\(PptxWriter.emptyTree)<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page \(i + 1)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\(s.x)\" y=\"\(s.y)\"/><a:ext cx=\"\(s.cx)\" cy=\"\(s.cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
            let rels = PptxWriter.head + "<Relationships xmlns=\"\(PptxWriter.relNS)\"><Relationship Id=\"rId1\" Type=\"\(PptxWriter.rt)slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"\(PptxWriter.rt)image\" Target=\"../media/image\(i + 1).jpeg\"/></Relationships>"
            z.add("ppt/slides/slide\(i + 1).xml", Data(slide.utf8))
            z.add("ppt/slides/_rels/slide\(i + 1).xml.rels", Data(rels.utf8))
            z.add("ppt/media/image\(i + 1).jpeg", s.jpeg, compress: false)
        }
        return z.finish()
    }

    static let theme = head + """
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="fs PDF IQ"><a:themeElements>\
    <a:clrScheme name="fs"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>\
    <a:dk2><a:srgbClr val="1F2328"/></a:dk2><a:lt2><a:srgbClr val="EEECE1"/></a:lt2>\
    <a:accent1><a:srgbClr val="D9000D"/></a:accent1><a:accent2><a:srgbClr val="008183"/></a:accent2>\
    <a:accent3><a:srgbClr val="9BBB59"/></a:accent3><a:accent4><a:srgbClr val="8064A2"/></a:accent4>\
    <a:accent5><a:srgbClr val="4BACC6"/></a:accent5><a:accent6><a:srgbClr val="F79646"/></a:accent6>\
    <a:hlink><a:srgbClr val="0000FF"/></a:hlink><a:folHlink><a:srgbClr val="800080"/></a:folHlink></a:clrScheme>\
    <a:fontScheme name="fs"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>\
    <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>\
    <a:fmtScheme name="fs"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>\
    <a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="38100"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>\
    <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>\
    <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>\
    </a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
    """
}
