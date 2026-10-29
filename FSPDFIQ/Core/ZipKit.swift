import Foundation
import Compression

// MARK: - CRC32

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf {
                crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Raw DEFLATE via Apple's Compression framework

enum Deflate {
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let cap = data.count + data.count / 10 + 1024
        var dst = [UInt8](repeating: 0, count: cap)
        let n = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&dst, cap, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard n > 0, n < data.count else { return nil }
        return Data(dst[0..<n])
    }

    static func decompress(_ data: Data, expected: Int) -> Data? {
        guard expected > 0 else { return Data() }
        var dst = [UInt8](repeating: 0, count: expected)
        let n = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&dst, expected, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard n > 0 else { return nil }
        return Data(dst[0..<n])
    }
}

// MARK: - ZIP writer

struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static func le16(_ v: UInt16, _ d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
    private static func le32(_ v: UInt32, _ d: inout Data) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
    }

    mutating func add(_ name: String, _ content: Data, compress: Bool = true) {
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(content)
        var method: UInt16 = 0
        var payload = content
        if compress, let c = Deflate.compress(content) { method = 8; payload = c }
        let offset = UInt32(body.count)
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = 0x21 // 1980-01-01

        ZipWriter.le32(0x04034b50, &body)
        ZipWriter.le16(20, &body)
        ZipWriter.le16(0x0800, &body)
        ZipWriter.le16(method, &body)
        ZipWriter.le16(dosTime, &body)
        ZipWriter.le16(dosDate, &body)
        ZipWriter.le32(crc, &body)
        ZipWriter.le32(UInt32(payload.count), &body)
        ZipWriter.le32(UInt32(content.count), &body)
        ZipWriter.le16(UInt16(nameData.count), &body)
        ZipWriter.le16(0, &body)
        body.append(nameData)
        body.append(payload)

        ZipWriter.le32(0x02014b50, &central)
        ZipWriter.le16(20, &central)
        ZipWriter.le16(20, &central)
        ZipWriter.le16(0x0800, &central)
        ZipWriter.le16(method, &central)
        ZipWriter.le16(dosTime, &central)
        ZipWriter.le16(dosDate, &central)
        ZipWriter.le32(crc, &central)
        ZipWriter.le32(UInt32(payload.count), &central)
        ZipWriter.le32(UInt32(content.count), &central)
        ZipWriter.le16(UInt16(nameData.count), &central)
        ZipWriter.le16(0, &central)
        ZipWriter.le16(0, &central)
        ZipWriter.le16(0, &central)
        ZipWriter.le16(0, &central)
        ZipWriter.le32(0, &central)
        ZipWriter.le32(offset, &central)
        central.append(nameData)
        count += 1
    }

    func finish() -> Data {
        var out = body
        let cdOffset = UInt32(out.count)
        out.append(central)
        ZipWriter.le32(0x06054b50, &out)
        ZipWriter.le16(0, &out)
        ZipWriter.le16(0, &out)
        ZipWriter.le16(count, &out)
        ZipWriter.le16(count, &out)
        ZipWriter.le32(UInt32(central.count), &out)
        ZipWriter.le32(cdOffset, &out)
        ZipWriter.le16(0, &out)
        return out
    }

    static func zip(files: [URL], to out: URL) throws {
        var z = ZipWriter()
        var used = Set<String>()
        for f in files {
            var name = f.lastPathComponent
            var i = 2
            while used.contains(name) { name = "\(i)-\(f.lastPathComponent)"; i += 1 }
            used.insert(name)
            let d = try Data(contentsOf: f)
            let ext = f.pathExtension.lowercased()
            let already = ["jpg", "jpeg", "png", "zip", "docx", "xlsx", "pptx", "jp2"].contains(ext)
            z.add(name, d, compress: !already)
        }
        try z.finish().write(to: out)
    }
}

// MARK: - ZIP reader

struct ZipReader {
    private(set) var entries: [String: Data] = [:]

    init(data: Data) throws {
        let b = [UInt8](data)
        func u16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | (Int(b[i + 1]) << 8) : 0 }
        func u32(_ i: Int) -> Int { i + 3 < b.count ? Int(b[i]) | (Int(b[i + 1]) << 8) | (Int(b[i + 2]) << 16) | (Int(b[i + 3]) << 24) : 0 }

        guard b.count > 22 else { throw IQError.cannotOpen }
        var eocd = -1
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_536)
        while i >= stop {
            if b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x05 && b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw IQError.cannotOpen }
        let total = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<total {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            let nameBytes = Array(b[(p + 46)..<min(b.count, p + 46 + nlen)])
            let name = String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nlen + elen + clen
            guard local + 30 <= b.count else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count, !name.hasSuffix("/") else { continue }
            let raw = Data(b[start..<(start + csize)])
            if method == 0 {
                entries[name] = raw
            } else if method == 8, let d = Deflate.decompress(raw, expected: usize) {
                entries[name] = d
            }
        }
    }

    subscript(_ name: String) -> Data? {
        if let d = entries[name] { return d }
        let n = name.hasPrefix("/") ? String(name.dropFirst()) : name
        return entries[n]
    }
}

// MARK: - Tiny XML DOM

final class XNode {
    let name: String
    var attrs: [String: String]
    var children: [XNode] = []
    var text = ""

    init(name: String, attrs: [String: String]) {
        self.name = name
        self.attrs = attrs
    }

    func child(_ n: String) -> XNode? { children.first { $0.name == n } }
    func all(_ n: String) -> [XNode] { children.filter { $0.name == n } }

    func first(_ n: String) -> XNode? {
        for c in children {
            if c.name == n { return c }
            if let f = c.first(n) { return f }
        }
        return nil
    }

    func descendants(_ n: String) -> [XNode] {
        var out: [XNode] = []
        for c in children {
            if c.name == n { out.append(c) }
            out.append(contentsOf: c.descendants(n))
        }
        return out
    }

    subscript(_ key: String) -> String? { attrs[key] }

    var allText: String {
        var s = text
        for c in children { s += c.allText }
        return s
    }
}

final class XParser: NSObject, XMLParserDelegate {
    private var stack: [XNode] = []
    private var root: XNode?

    static func parse(_ data: Data?) -> XNode? {
        guard let data = data else { return nil }
        let p = XMLParser(data: data)
        let d = XParser()
        p.delegate = d
        p.shouldProcessNamespaces = false
        p.shouldResolveExternalEntities = false
        _ = p.parse()
        return d.root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let n = XNode(name: elementName, attrs: attributeDict)
        if let top = stack.last { top.children.append(n) } else { root = n }
        stack.append(n)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }
}

/// Parses an OOXML .rels file into [Id: Target]
func parseRels(_ data: Data?) -> [String: String] {
    guard let root = XParser.parse(data) else { return [:] }
    var out: [String: String] = [:]
    for r in root.all("Relationship") {
        if let id = r["Id"], let t = r["Target"] { out[id] = t }
    }
    return out
}

func parseRelTypes(_ data: Data?) -> [(id: String, type: String, target: String)] {
    guard let root = XParser.parse(data) else { return [] }
    return root.all("Relationship").compactMap { r in
        guard let id = r["Id"], let t = r["Target"] else { return nil }
        return (id, r["Type"] ?? "", t)
    }
}

/// Resolve an OOXML relative target ("../media/image1.png") against the folder of `base` ("ppt/slides/slide1.xml").
func resolvePath(base: String, target: String) -> String {
    if target.hasPrefix("/") { return String(target.dropFirst()) }
    var parts = base.split(separator: "/").map(String.init)
    if !parts.isEmpty { parts.removeLast() }
    for comp in target.split(separator: "/").map(String.init) {
        if comp == ".." { if !parts.isEmpty { parts.removeLast() } }
        else if comp != "." { parts.append(comp) }
    }
    return parts.joined(separator: "/")
}

func relsPath(for path: String) -> String {
    let ns = path as NSString
    return ns.deletingLastPathComponent + "/_rels/" + ns.lastPathComponent + ".rels"
}
