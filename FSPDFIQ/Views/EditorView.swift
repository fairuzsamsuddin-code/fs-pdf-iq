import SwiftUI
import PDFKit
import PhotosUI
import PencilKit

enum EditTool: String, CaseIterable, Identifiable {
    case pan, text, whiteout, highlight, rect, draw, check, cross, signature, image, redact
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .pan: return "hand.point.up.left"
        case .text: return "textformat"
        case .whiteout: return "eraser"
        case .highlight: return "highlighter"
        case .rect: return "rectangle"
        case .draw: return "scribble"
        case .check: return "checkmark"
        case .cross: return "xmark"
        case .signature: return "signature"
        case .image: return "photo"
        case .redact: return "rectangle.fill"
        }
    }
    var label: String {
        switch self {
        case .pan: return L("Scroll", "Skrol")
        case .text: return L("Text", "Teks")
        case .whiteout: return L("Whiteout", "Padam putih")
        case .highlight: return L("Highlight", "Serlah")
        case .rect: return L("Box", "Kotak")
        case .draw: return L("Draw", "Lukis")
        case .check: return L("Tick", "Tanda")
        case .cross: return L("Cross", "Pangkah")
        case .signature: return L("Sign", "Tandatangan")
        case .image: return L("Image", "Imej")
        case .redact: return L("Redact", "Redaksi")
        }
    }
    var isDrag: Bool { [.whiteout, .highlight, .rect, .draw, .redact].contains(self) }
}

final class EditorModel: ObservableObject {
    let pdfView: PDFView
    let doc: PDFDocument
    @Published var tool: EditTool = .pan
    @Published var color: UIColor = .black
    @Published var fontSize: CGFloat = 14
    @Published var signature: UIImage?
    @Published var stampImage: UIImage?
    @Published var undoCount = 0
    private var added: [(PDFPage, PDFAnnotation)] = []

    init(doc: PDFDocument) {
        self.doc = doc
        self.pdfView = makePDFView(doc)
        if let data = UserDefaults.standard.data(forKey: "fsiq.signature"), let img = UIImage(data: data) { signature = img }
    }

    func add(_ a: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(a)
        added.append((page, a))
        undoCount = added.count
    }

    func undo() {
        guard let (p, a) = added.popLast() else { return }
        p.removeAnnotation(a)
        undoCount = added.count
    }

    func pagePoint(_ viewPoint: CGPoint) -> (PDFPage, CGPoint)? {
        guard let page = pdfView.page(for: viewPoint, nearest: true) else { return nil }
        return (page, pdfView.convert(viewPoint, to: page))
    }

    func noBorder() -> PDFBorder { let b = PDFBorder(); b.lineWidth = 0; return b }

    func placeText(_ text: String, at viewPoint: CGPoint) {
        guard !text.isEmpty, let (page, pt) = pagePoint(viewPoint) else { return }
        let font = UIFont.systemFont(ofSize: fontSize)
        let size = (text as NSString).boundingRect(with: CGSize(width: 400, height: 2000), options: [.usesLineFragmentOrigin],
                                                   attributes: [.font: font], context: nil).size
        let rect = CGRect(x: pt.x, y: pt.y - size.height, width: size.width + 12, height: size.height + 6)
        let a = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        a.contents = text
        a.font = font
        a.fontColor = color
        a.color = .clear
        a.border = noBorder()
        add(a, to: page)
    }

    func placeMark(_ symbol: String, at viewPoint: CGPoint) {
        guard let (page, pt) = pagePoint(viewPoint) else { return }
        let s = max(16, fontSize * 1.6)
        let a = PDFAnnotation(bounds: CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s * 1.1, height: s * 1.2), forType: .freeText, withProperties: nil)
        a.contents = symbol
        a.font = UIFont.systemFont(ofSize: s, weight: .bold)
        a.fontColor = symbol == "✓" ? UIColor(red: 0, green: 0.55, blue: 0.25, alpha: 1) : .fsRed
        a.color = .clear
        a.border = noBorder()
        add(a, to: page)
    }

    func placeImage(_ img: UIImage, at viewPoint: CGPoint, width: CGFloat) {
        guard let (page, pt) = pagePoint(viewPoint) else { return }
        let h = width * img.size.height / max(1, img.size.width)
        let a = ImageAnnotation(bounds: CGRect(x: pt.x - width / 2, y: pt.y - h / 2, width: width, height: h), forType: .stamp, withProperties: nil)
        a.image = img
        add(a, to: page)
    }

    func placeRect(from a: CGPoint, to b: CGPoint) {
        guard let (page, p1) = pagePoint(a) else { return }
        let p2 = pdfView.convert(b, to: page)
        let r = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
        guard r.width > 3, r.height > 3 else { return }
        let ann = PDFAnnotation(bounds: r, forType: .square, withProperties: nil)
        switch tool {
        case .whiteout:
            ann.color = .white; ann.interiorColor = .white; ann.border = noBorder()
        case .highlight:
            ann.color = .clear; ann.interiorColor = UIColor.systemYellow.withAlphaComponent(0.38); ann.border = noBorder()
        case .redact:
            ann.color = .black; ann.interiorColor = .black; ann.border = noBorder(); ann.userName = StampEngine.redactTag
        default:
            ann.color = color; let b = PDFBorder(); b.lineWidth = 2; ann.border = b
        }
        add(ann, to: page)
    }

    func placeInk(_ points: [CGPoint]) {
        guard points.count > 1, let (page, _) = pagePoint(points[0]) else { return }
        let pts = points.map { pdfView.convert($0, to: page) }
        let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!, minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
        let bounds = CGRect(x: minX - 4, y: minY - 4, width: maxX - minX + 8, height: maxY - minY + 8)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: pts[0].x - bounds.minX, y: pts[0].y - bounds.minY))
        for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY)) }
        let a = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        a.color = color
        let b = PDFBorder(); b.lineWidth = 2.5; a.border = b
        a.add(path)
        add(a, to: page)
    }

    func redact(term: String) -> Int {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return 0 }
        var n = 0
        for sel in doc.findString(t, withOptions: [.caseInsensitive]) {
            for page in sel.pages {
                let r = sel.bounds(for: page).insetBy(dx: -1.5, dy: -1.5)
                let ann = PDFAnnotation(bounds: r, forType: .square, withProperties: nil)
                ann.color = .black; ann.interiorColor = .black; ann.border = noBorder(); ann.userName = StampEngine.redactTag
                add(ann, to: page)
                n += 1
            }
        }
        return n
    }
}

/// Transparent layer over the PDF that captures taps / drags for the active tool.
struct TouchOverlay: UIViewRepresentable {
    @ObservedObject var model: EditorModel
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> OverlayView {
        let v = OverlayView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: OverlayView, context: Context) {
        v.model = model
        v.onTap = onTap
        v.isUserInteractionEnabled = model.tool != .pan
    }

    final class OverlayView: UIView {
        var model: EditorModel?
        var onTap: ((CGPoint) -> Void)?
        private var start: CGPoint = .zero
        private var points: [CGPoint] = []
        private let shape = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            shape.fillColor = UIColor.fsTeal.withAlphaComponent(0.15).cgColor
            shape.strokeColor = UIColor.fsTeal.cgColor
            shape.lineWidth = 2
            layer.addSublayer(shape)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            start = t.location(in: self)
            points = [start]
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first, let m = model else { return }
            let p = t.location(in: self)
            points.append(p)
            if m.tool == .draw {
                let path = UIBezierPath()
                path.move(to: points[0])
                for q in points.dropFirst() { path.addLine(to: q) }
                shape.fillColor = UIColor.clear.cgColor
                shape.path = path.cgPath
            } else if m.tool.isDrag {
                shape.fillColor = (m.tool == .redact ? UIColor.black : UIColor.fsTeal).withAlphaComponent(0.25).cgColor
                shape.path = UIBezierPath(rect: CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))).cgPath
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first, let m = model else { return }
            let end = t.location(in: self)
            shape.path = nil
            let pdfView = m.pdfView
            let s = convert(start, to: pdfView), e = convert(end, to: pdfView)
            if m.tool == .draw {
                m.placeInk(points.map { convert($0, to: pdfView) })
            } else if m.tool.isDrag {
                m.placeRect(from: s, to: e)
            } else if hypot(end.x - start.x, end.y - start.y) < 12 {
                onTap?(e)
            }
            points = []
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { shape.path = nil; points = [] }
    }
}

struct EditorScreen: View {
    enum Mode { case edit, sign, redact }
    let tool: Tool
    let mode: Mode
    var onSave: ((Data) -> Void)? = nil
    @State private var url: URL?
    @StateObject private var holder = EditorHolder()

    init(tool: Tool, mode: Mode, initialFiles: [URL], onSave: ((Data) -> Void)? = nil) {
        self.tool = tool
        self.mode = mode
        self.onSave = onSave
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if let m = holder.model {
                EditorContent(model: m, mode: mode, name: url.map { Workspace.base($0) } ?? "document", onSave: onSave)
            } else {
                PickPDFPrompt(tool: tool) { url = $0 }
            }
        }
        .task(id: url) {
            guard let u = url, holder.model == nil, let d = try? PDFIO.open(u) else { return }
            let m = EditorModel(doc: d)
            if mode == .sign { m.tool = .signature } else if mode == .redact { m.tool = .redact }
            holder.model = m
        }
    }
}

final class EditorHolder: ObservableObject { @Published var model: EditorModel? }

struct EditorContent: View {
    @ObservedObject var model: EditorModel
    let mode: EditorScreen.Mode
    let name: String
    let onSave: ((Data) -> Void)?

    @State private var pendingPoint: CGPoint?
    @State private var showTextPrompt = false
    @State private var text = ""
    @State private var showSignaturePad = false
    @State private var photoItem: PhotosPickerItem?
    @State private var searchTerm = ""
    @State private var info: String?
    @State private var result: ToolResult?
    @State private var showResult = false
    @State private var busy = false
    @State private var stampWidth: CGFloat = 160

    private var tools: [EditTool] {
        switch mode {
        case .edit: return [.pan, .text, .whiteout, .highlight, .rect, .draw, .check, .cross, .signature, .image]
        case .sign: return [.pan, .signature, .text, .check, .cross]
        case .redact: return [.pan, .redact]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PDFKitView(pdfView: model.pdfView)
                TouchOverlay(model: model) { p in handleTap(p) }
            }
            toolbar
        }
        .background(AppBackground())
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoCount == 0)
                Button { save() } label: {
                    if busy { ProgressView() } else { Text(mode == .redact ? L("Apply", "Guna") : L("Save", "Simpan")).bold() }
                }
                .disabled(busy)
            }
        }
        .alert(L("Add text", "Tambah teks"), isPresented: $showTextPrompt) {
            TextField(L("Type here", "Taip di sini"), text: $text)
            Button(L("Cancel", "Batal"), role: .cancel) {}
            Button(L("Add", "Tambah")) { if let p = pendingPoint { model.placeText(text, at: p) }; text = "" }
        }
        .sheet(isPresented: $showSignaturePad) {
            SignaturePad { img in
                model.signature = img
                if let d = img.pngData() { UserDefaults.standard.set(d, forKey: "fsiq.signature") }
                model.tool = .signature
                info = L("Tap the page where the signature should go.", "Ketik halaman di mana tandatangan patut diletakkan.")
            }
        }
        .sheet(isPresented: $showResult) {
            NavigationStack {
                ScrollView { if let r = result { ResultsSection(result: r).padding(16) } }
                    .background(AppBackground())
                    .navigationTitle(L("Saved", "Disimpan"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done", "Selesai")) { showResult = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: photoItem) { item in
            guard let item = item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await MainActor.run {
                        model.stampImage = Draw.normalized(img, maxSide: 1600)
                        model.tool = .image
                        info = L("Tap the page to place the image.", "Ketik halaman untuk meletakkan imej.")
                    }
                }
            }
        }
        .onAppear {
            if mode == .sign && model.signature == nil { showSignaturePad = true }
            if mode == .redact { info = L("Drag over text to black it out, or search below. Apply makes it permanent.", "Seret ke atas teks untuk menghitamkannya, atau cari di bawah. Guna menjadikannya kekal.") }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            if let i = info {
                Text(i).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            if mode == .redact {
                HStack {
                    TextField(L("Find text to redact (e.g. IC number)", "Cari teks untuk diredaksi (cth. nombor IC)"), text: $searchTerm)
                        .fieldStyle()
                    Button(L("Mark all", "Tanda semua")) {
                        let n = model.redact(term: searchTerm)
                        info = L("\(n) match(es) marked.", "\(n) padanan ditanda.")
                    }
                    .buttonStyle(SoftButtonStyle(tint: .fsRed))
                }
                .padding(.horizontal, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tools) { t in
                        Button {
                            select(t)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: t.icon).font(.system(size: 17, weight: .semibold))
                                Text(t.label).font(.system(size: 10, weight: .medium))
                            }
                            .frame(width: 62, height: 50)
                            .foregroundColor(model.tool == t ? .white : .primary)
                            .background(model.tool == t ? Color.fsRed : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if mode == .edit {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            VStack(spacing: 3) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 17, weight: .semibold))
                                Text(L("Pick", "Pilih")).font(.system(size: 10, weight: .medium))
                            }
                            .frame(width: 62, height: 50)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            if [.text, .rect, .draw].contains(model.tool) {
                HStack(spacing: 12) {
                    ForEach([UIColor.black, .fsRed, .fsTeal, .systemBlue], id: \.self) { c in
                        Circle().fill(Color(c)).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(model.color == c ? 0.8 : 0), lineWidth: 2).padding(-3))
                            .onTapGesture { model.color = c }
                    }
                    if model.tool == .text {
                        Stepper("\(Int(model.fontSize)) pt", value: $model.fontSize, in: 8...48)
                    }
                }
                .padding(.horizontal, 16)
            }
            if model.tool == .signature || model.tool == .image {
                HStack {
                    Text(L("Size", "Saiz")).font(.caption)
                    Slider(value: $stampWidth, in: 60...360).tint(.fsTeal)
                    if model.tool == .signature {
                        Button(L("New signature", "Tandatangan baharu")) { showSignaturePad = true }.font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func select(_ t: EditTool) {
        model.tool = t
        switch t {
        case .pan: info = nil
        case .text: info = L("Tap where the text should start.", "Ketik di mana teks patut bermula.")
        case .whiteout: info = L("Drag over content to cover it with white.", "Seret ke atas kandungan untuk menutupnya dengan putih.")
        case .highlight: info = L("Drag over text to highlight it.", "Seret ke atas teks untuk menyerlahkannya.")
        case .rect: info = L("Drag to draw a box.", "Seret untuk melukis kotak.")
        case .draw: info = L("Draw with your finger or Apple Pencil.", "Lukis dengan jari atau Apple Pencil.")
        case .check, .cross: info = L("Tap to stamp.", "Ketik untuk mengecop.")
        case .signature:
            if model.signature == nil { showSignaturePad = true }
            info = L("Tap the page where the signature should go.", "Ketik halaman di mana tandatangan patut diletakkan.")
        case .image:
            info = model.stampImage == nil ? L("Pick a photo first.", "Pilih foto dahulu.") : L("Tap the page to place the image.", "Ketik halaman untuk meletakkan imej.")
        case .redact: info = L("Drag over text to black it out.", "Seret ke atas teks untuk menghitamkannya.")
        }
    }

    private func handleTap(_ p: CGPoint) {
        switch model.tool {
        case .text: pendingPoint = p; showTextPrompt = true
        case .check: model.placeMark("✓", at: p)
        case .cross: model.placeMark("✗", at: p)
        case .signature: if let s = model.signature { model.placeImage(s, at: p, width: stampWidth) } else { showSignaturePad = true }
        case .image: if let s = model.stampImage { model.placeImage(s, at: p, width: stampWidth) }
        default: break
        }
    }

    private func save() {
        busy = true
        let doc = model.doc
        let redact = mode == .redact
        let name = self.name
        DispatchQueue.main.async {
            do {
                let data = try (redact ? StampEngine.applyRedactions(doc) : OptimizeEngine.flatten(doc))
                if let cb = onSave { cb(data); busy = false; return }
                let out = Workspace.unique(Workspace.newDir("Out"), name + (redact ? "_redacted.pdf" : (mode == .sign ? "_signed.pdf" : "_edited.pdf")))
                try data.write(to: out)
                result = ToolResult(files: [out], message: redact ? L("Redactions are permanent — the hidden text is gone from the file.", "Redaksi adalah kekal — teks tersembunyi telah dibuang daripada fail.") : nil)
                showResult = true
            } catch {
                info = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Signature pad

struct SignaturePad: View {
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var typed = ""
    @State private var fontIndex = 0
    @State private var inkBlue = false
    @State private var canvas = PKCanvasView()

    private let fonts = ["SnellRoundhand-Bold", "BradleyHandITCTT-Bold", "Zapfino", "Noteworthy-Bold"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("", selection: $mode) {
                    Text(L("Draw", "Lukis")).tag(0)
                    Text(L("Type", "Taip")).tag(1)
                }
                .pickerStyle(.segmented)
                Toggle(L("Blue ink", "Dakwat biru"), isOn: $inkBlue).tint(.fsTeal)
                if mode == 0 {
                    CanvasRepresentable(canvas: $canvas, color: inkBlue ? UIColor(red: 0.05, green: 0.2, blue: 0.65, alpha: 1) : .black)
                        .frame(height: 220)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.3)))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.secondary.opacity(0.35)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 50)
                        }
                    Button(L("Clear", "Kosongkan")) { canvas.drawing = PKDrawing() }.buttonStyle(SoftButtonStyle())
                } else {
                    TextField(L("Your name", "Nama anda"), text: $typed).fieldStyle()
                    ForEach(0..<fonts.count, id: \.self) { i in
                        Text(typed.isEmpty ? "Fairuz" : typed)
                            .font(.custom(fonts[i], size: 30))
                            .foregroundColor(inkBlue ? Color(red: 0.05, green: 0.2, blue: 0.65) : .black)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(fontIndex == i ? Color.fsTeal : Color.clear, lineWidth: 2))
                            .onTapGesture { fontIndex = i }
                    }
                }
                Spacer()
                Button(L("Use this signature", "Guna tandatangan ini")) {
                    if let img = makeImage() { onDone(img); dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .navigationTitle(L("Your signature", "Tandatangan anda"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "Batal")) { dismiss() } } }
        }
    }

    private func makeImage() -> UIImage? {
        if mode == 0 {
            let d = canvas.drawing
            guard !d.bounds.isEmpty else { return nil }
            return d.image(from: d.bounds.insetBy(dx: -6, dy: -6), scale: 3)
        }
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let font = UIFont(name: fonts[fontIndex], size: 72) ?? UIFont.italicSystemFont(ofSize: 72)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: inkBlue ? UIColor(red: 0.05, green: 0.2, blue: 0.65, alpha: 1) : UIColor.black]
        let size = (name as NSString).size(withAttributes: attrs)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        fmt.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: size.width + 20, height: size.height + 10), format: fmt).image { _ in
            (name as NSString).draw(at: CGPoint(x: 10, y: 5), withAttributes: attrs)
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    let color: UIColor

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: color, width: 5)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pen, color: color, width: 5)
    }
}
