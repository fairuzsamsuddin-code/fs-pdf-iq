import SwiftUI
import PDFKit
import VisionKit
import AVFoundation
import PhotosUI

// MARK: - Crop

struct CropView: View {
    let tool: Tool
    @State private var url: URL?
    @State private var doc: PDFDocument?
    @State private var top = 0.05
    @State private var bottom = 0.05
    @State private var left = 0.05
    @State private var right = 0.05
    @State private var range = ""
    @State private var result: ToolResult?
    @State private var error: String?

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if let d = doc, let first = d.page(at: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        let size = first.displaySize
                        let h: CGFloat = 340
                        let w = h * size.width / max(1, size.height)
                        ZStack(alignment: .topLeading) {
                            PageThumb(page: first, size: CGSize(width: w, height: h))
                            Path { p in
                                p.addRect(CGRect(x: 0, y: 0, width: w, height: h))
                                p.addRect(CGRect(x: w * left, y: h * top, width: w * (1 - left - right), height: h * (1 - top - bottom)))
                            }
                            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                            Rectangle().strokeBorder(Color.fsRed, lineWidth: 2)
                                .frame(width: w * (1 - left - right), height: h * (1 - top - bottom))
                                .offset(x: w * left, y: h * top)
                        }
                        .frame(width: w, height: h)
                        VStack(spacing: 10) {
                            slider(L("Top", "Atas"), $top)
                            slider(L("Bottom", "Bawah"), $bottom)
                            slider(L("Left", "Kiri"), $left)
                            slider(L("Right", "Kanan"), $right)
                            OptionRow(title: L("Pages", "Halaman")) {
                                TextField(L("All pages — or e.g. 1-3, 5", "Semua halaman — atau cth. 1-3, 5"), text: $range).fieldStyle()
                            }
                        }
                        .padding(16).glass(22)
                        if let e = error { ErrorBanner(text: e) }
                        RunButton(title: L("Crop", "Pangkas"), busy: false, progress: 0, enabled: true, action: run)
                        if let r = result { ResultsSection(result: r) }
                    }
                    .padding(16)
                }
                .background(AppBackground())
            } else {
                PickPDFPrompt(tool: tool) { url = $0 }
            }
        }
        .task(id: url) {
            guard let u = url else { return }
            do { doc = try PDFIO.open(u) } catch { self.error = error.localizedDescription; url = nil }
        }
    }

    private func slider(_ title: String, _ v: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.footnote.weight(.semibold)).frame(width: 64, alignment: .leading)
            Slider(value: v, in: 0...0.4).tint(.fsTeal)
            Text("\(Int(v.wrappedValue * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
        }
    }

    private func run() {
        guard let u = url else { return }
        let out = Workspace.unique(Workspace.newDir("Out"), Workspace.base(u) + "_cropped.pdf")
        do {
            try OptimizeEngine.crop(u, insets: .init(top: top, bottom: bottom, left: left, right: right), range: range, out: out)
            result = ToolResult(files: [out]); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Scan

struct ScanView: View {
    let tool: Tool
    @State private var images: [UIImage] = []
    @State private var showScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var filter = 0
    @State private var ocr = false
    @State private var busy = false
    @State private var result: ToolResult?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ToolHeader(tool: tool)
                VStack(spacing: 12) {
                    if VNDocumentCameraViewController.isSupported {
                        Button { showScanner = true } label: { Label(L("Scan with camera", "Imbas dengan kamera"), systemImage: "camera.viewfinder") }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Text(L("Camera scanning isn't available on this device — add photos instead.", "Imbasan kamera tiada pada peranti ini — tambah foto sebaliknya."))
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 50, matching: .images) {
                        Label(L("Add from Photos", "Tambah dari Foto"), systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .padding(16).glass(22)

                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 90, height: 120).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button { images.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.white).shadow(radius: 2) }.padding(4)
                                    }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: L("Filter", "Penapis"))
                        Picker("", selection: $filter) {
                            Text(L("Magic", "Ajaib")).tag(0); Text(L("B&W", "H&P")).tag(1); Text(L("Gray", "Kelabu")).tag(2); Text(L("Original", "Asal")).tag(3)
                        }.pickerStyle(.segmented)
                        Toggle(L("Make text searchable (OCR)", "Jadikan teks boleh dicari (OCR)"), isOn: $ocr).tint(.fsTeal)
                    }
                    .padding(16).glass(22)
                    if let e = error { ErrorBanner(text: e) }
                    RunButton(title: L("Create PDF (\(images.count) pages)", "Hasilkan PDF (\(images.count) halaman)"), busy: busy, progress: 0, enabled: true, action: run)
                }
                if let r = result { ResultsSection(result: r) }
            }
            .padding(16)
        }
        .background(AppBackground())
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { scanned in images.append(contentsOf: scanned); showScanner = false }
                .ignoresSafeArea()
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [UIImage] = []
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { loaded.append(Draw.normalized(img)) }
                }
                await MainActor.run { images.append(contentsOf: loaded); photoItems = [] }
            }
        }
    }

    private func run() {
        busy = true; error = nil
        let imgs = images, f = filter, doOCR = ocr
        Task.detached(priority: .userInitiated) {
            do {
                let enhanced = imgs.compactMap { $0.cgImage }.map { OptimizeEngine.enhance($0, mode: f) ?? $0 }
                let dir = Workspace.newDir("Out")
                let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")
                var files: [URL]
                if doOCR {
                    var urls: [URL] = []
                    let tmp = Workspace.newDir("Work")
                    for (i, img) in enhanced.enumerated() {
                        let u = tmp.appendingPathComponent(String(format: "Scan_%03d.jpg", i + 1))
                        try UIImage(cgImage: img).jpegData(compressionQuality: 0.85)?.write(to: u)
                        urls.append(u)
                    }
                    let r = try OCREngine.run(urls, malay: true, outDir: dir, progress: nil)
                    files = [r.pdf, r.txt]
                } else {
                    let u = Workspace.unique(dir, "Scan \(stamp).pdf")
                    try OptimizeEngine.imagesPDF(enhanced, quality: 0.8, a4Fit: true).write(to: u)
                    files = [u]
                }
                let final = files
                await MainActor.run { result = ToolResult(files: final); busy = false }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; busy = false }
            }
        }
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var imgs: [UIImage] = []
            for i in 0..<scan.pageCount { imgs.append(Draw.normalized(scan.imageOfPage(at: i))) }
            onFinish(imgs)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}

// MARK: - Listen

final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    @Published var speaking = false
    @Published var paused = false
    @Published var spoken = NSRange(location: 0, length: 0)
    @Published var note: String?
    private(set) var text = ""

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ t: String, malay: Bool, rate: Float) {
        stop()
        text = t
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: t)
        if malay {
            if let v = AVSpeechSynthesisVoice(language: "ms-MY") { u.voice = v; note = nil }
            else { u.voice = AVSpeechSynthesisVoice(language: "id-ID"); note = L("No Malay voice installed — using Indonesian. Add a Malay voice in Settings › Accessibility › Spoken Content › Voices.", "Tiada suara Melayu dipasang — menggunakan Indonesia. Tambah suara Melayu di Tetapan › Kebolehcapaian › Kandungan Dituturkan › Suara.") }
        } else {
            u.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
            note = nil
        }
        u.rate = rate
        synth.speak(u)
        speaking = true
        paused = false
    }

    func togglePause() {
        if synth.isPaused { synth.continueSpeaking(); paused = false } else { synth.pauseSpeaking(at: .word); paused = true }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
        paused = false
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.spoken = r }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false; self.paused = false }
    }
}

struct ListenView: View {
    let tool: Tool
    @State private var url: URL?
    @State private var pages: [String] = []
    @State private var startPage = 0
    @State private var malay = AppSettings.shared.lang == .ms
    @State private var rate: Float = 0.5
    @StateObject private var speaker = Speaker()
    @State private var error: String?

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if !pages.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("", selection: $malay) { Text("Bahasa Melayu").tag(true); Text("English").tag(false) }.pickerStyle(.segmented)
                            HStack {
                                Image(systemName: "tortoise.fill").foregroundColor(.secondary)
                                Slider(value: $rate, in: 0.3...0.65).tint(.fsTeal)
                                Image(systemName: "hare.fill").foregroundColor(.secondary)
                            }
                            Picker(L("Start from", "Mula dari"), selection: $startPage) {
                                ForEach(0..<pages.count, id: \.self) { Text(L("Page \($0 + 1)", "Halaman \($0 + 1)")).tag($0) }
                            }
                            .pickerStyle(.menu)
                            HStack(spacing: 12) {
                                Button {
                                    if speaker.speaking { speaker.togglePause() } else {
                                        speaker.speak(pages[startPage...].joined(separator: "\n\n"), malay: malay, rate: rate)
                                    }
                                } label: {
                                    Label(speaker.speaking ? (speaker.paused ? L("Resume", "Sambung") : L("Pause", "Jeda")) : L("Play", "Main"),
                                          systemImage: speaker.speaking && !speaker.paused ? "pause.fill" : "play.fill")
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                Button { speaker.stop() } label: { Image(systemName: "stop.fill").frame(width: 50) }
                                    .buttonStyle(PrimaryButtonStyle(color: .fsTeal))
                                    .frame(width: 80)
                            }
                            if let n = speaker.note { Text(n).font(.caption).foregroundColor(.secondary) }
                        }
                        .padding(16).glass(22)
                        Text(highlighted)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).glass(22)
                    }
                    .padding(16)
                }
                .background(AppBackground())
            } else {
                VStack {
                    if let e = error { ErrorBanner(text: e).padding() }
                    PickPDFPrompt(tool: tool) { url = $0 }
                }
            }
        }
        .task(id: url) {
            guard let u = url else { return }
            do {
                let d = try PDFIO.open(u)
                let p = (0..<d.pageCount).map { d.page(at: $0)?.string ?? "" }
                if p.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    error = L("No readable text — this looks like a scan. Run OCR PDF first.", "Tiada teks boleh dibaca — ini kelihatan seperti imbasan. Jalankan OCR PDF dahulu.")
                    url = nil
                } else { pages = p }
            } catch { self.error = error.localizedDescription; url = nil }
        }
        .onDisappear { speaker.stop() }
    }

    private var highlighted: AttributedString {
        let full = speaker.speaking || speaker.paused ? speaker.text : pages[startPage...].joined(separator: "\n\n")
        let shown = String(full.prefix(12000))
        var a = AttributedString(shown)
        let r = speaker.spoken
        if speaker.speaking, r.location + r.length <= (shown as NSString).length, let range = Range(r, in: shown), let ar = Range(range, in: a) {
            a[ar].backgroundColor = Color.fsTeal.opacity(0.25)
            a[ar].foregroundColor = .primary
        }
        return a
    }
}

// MARK: - Preview

struct PreviewScreen: View {
    let tool: Tool
    @State private var url: URL?
    @State private var pdfView: PDFView?
    @State private var search = ""
    @State private var matches: [PDFSelection] = []
    @State private var current = 0
    @State private var error: String?

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if let v = pdfView, let u = url {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        TextField(L("Search in document", "Cari dalam dokumen"), text: $search).fieldStyle().onSubmit { find(v) }
                        if !matches.isEmpty {
                            Text("\(current + 1)/\(matches.count)").font(.caption.monospacedDigit())
                            Button { step(v, 1) } label: { Image(systemName: "chevron.down") }
                        }
                    }
                    .padding(10)
                    PDFKitView(pdfView: v)
                    ThumbStrip(pdfView: v).frame(height: 76)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button { printDoc(u) } label: { Image(systemName: "printer") }
                        ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            } else {
                VStack {
                    if let e = error { ErrorBanner(text: e).padding() }
                    PickPDFPrompt(tool: tool) { url = $0 }
                }
            }
        }
        .task(id: url) {
            guard let u = url else { return }
            do { pdfView = makePDFView(try PDFIO.open(u)) } catch { self.error = error.localizedDescription; url = nil }
        }
    }

    private func find(_ v: PDFView) {
        matches = v.document?.findString(search, withOptions: [.caseInsensitive]) ?? []
        current = 0
        if let f = matches.first {
            f.color = UIColor.systemYellow
            v.highlightedSelections = matches
            v.go(to: f)
        }
    }

    private func step(_ v: PDFView, _ d: Int) {
        guard !matches.isEmpty else { return }
        current = (current + d) % matches.count
        v.go(to: matches[current])
        v.setCurrentSelection(matches[current], animate: true)
    }

    private func printDoc(_ u: URL) {
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = u.lastPathComponent
        pc.printInfo = info
        pc.printingItem = u
        _ = pc.present(animated: true, completionHandler: nil)
    }
}

struct ThumbStrip: UIViewRepresentable {
    let pdfView: PDFView
    func makeUIView(context: Context) -> PDFThumbnailView {
        let t = PDFThumbnailView()
        t.pdfView = pdfView
        t.layoutMode = .horizontal
        t.thumbnailSize = CGSize(width: 44, height: 60)
        t.backgroundColor = .secondarySystemBackground
        return t
    }
    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {}
}

// MARK: - AI summary

struct AIView: View {
    let tool: Tool
    @State private var url: URL?
    @State private var text = ""
    @State private var task = 0
    @State private var answerMalay = AppSettings.shared.lang == .ms
    @State private var copied = false
    @State private var error: String?

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _url = State(initialValue: initialFiles.first)
    }

    private var tasks: [(String, String)] {
        [
            (L("Summary", "Ringkasan"), "Summarise this document in clear paragraphs, then list the 5 most important points."),
            (L("Key points", "Isi penting"), "Extract the key points as a concise bullet list, grouped by topic."),
            (L("Action items", "Tindakan"), "List every action item, deadline, amount and responsible party mentioned in this document."),
            (L("Quiz me", "Kuiz"), "Create 10 multiple-choice questions (with answers at the end) to test understanding of this document."),
            (L("Explain simply", "Terang mudah"), "Explain this document in simple language for a non-expert, with a short example."),
            (L("Study notes", "Nota belajar"), "Turn this document into structured study notes with headings, definitions and a short summary.")
        ]
    }

    private var prompt: String {
        let lang = answerMalay ? "Answer in Bahasa Melayu." : "Answer in English."
        let body = text.count > 60000 ? String(text.prefix(60000)) + "\n[...truncated]" : text
        return "\(tasks[task].1) \(lang)\n\n--- DOCUMENT ---\n\(body)"
    }

    var body: some View {
        Group {
            if !text.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(text: L("What do you want?", "Apa yang anda mahu?"))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                                ForEach(0..<tasks.count, id: \.self) { i in
                                    Button { task = i } label: {
                                        Text(tasks[i].0).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                            .foregroundColor(task == i ? .white : .primary)
                                            .background(task == i ? Color.fsRed : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                }
                            }
                            Picker("", selection: $answerMalay) { Text("Bahasa Melayu").tag(true); Text("English").tag(false) }.pickerStyle(.segmented)
                            Text(L("\(text.count) characters of text ready.", "\(text.count) aksara teks sedia.")).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(16).glass(22)

                        VStack(spacing: 10) {
                            ShareLink(item: prompt) { Label(L("Send to an AI app…", "Hantar ke aplikasi AI…"), systemImage: "square.and.arrow.up") }
                                .buttonStyle(PrimaryButtonStyle())
                            Button {
                                UIPasteboard.general.string = prompt
                                copied = true
                            } label: { Label(copied ? L("Copied!", "Disalin!") : L("Copy prompt + text", "Salin arahan + teks"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                                .buttonStyle(PrimaryButtonStyle(color: .fsTeal))
                            HStack(spacing: 8) {
                                aiLink("ChatGPT", "https://chatgpt.com/")
                                aiLink("Claude", "https://claude.ai/new")
                                aiLink("Gemini", "https://gemini.google.com/app")
                            }
                            Text(L("Opening a site copies the prompt first — just paste it in. Your text only leaves the device when you send it.",
                                   "Membuka laman akan menyalin arahan dahulu — tampal sahaja. Teks anda hanya keluar dari peranti apabila anda menghantarnya."))
                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(16).glass(22)
                    }
                    .padding(16)
                }
                .background(AppBackground())
            } else {
                VStack {
                    if let e = error { ErrorBanner(text: e).padding() }
                    PickPDFPrompt(tool: tool) { url = $0 }
                }
            }
        }
        .task(id: url) {
            guard let u = url else { return }
            do {
                let t = ConvertEngine.pdfText(try PDFIO.open(u))
                if t.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                    error = L("No readable text — run OCR PDF first.", "Tiada teks boleh dibaca — jalankan OCR PDF dahulu."); url = nil
                } else { text = t }
            } catch { self.error = error.localizedDescription; url = nil }
        }
    }

    private func aiLink(_ name: String, _ link: String) -> some View {
        Button {
            UIPasteboard.general.string = prompt
            copied = true
            if let u = URL(string: link) { UIApplication.shared.open(u) }
        } label: {
            Text(name).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftButtonStyle())
    }
}

// MARK: - Metadata

struct MetadataView: View {
    let tool: Tool
    @State private var url: URL?
    @State private var fields: [String: String] = [:]
    @State private var loaded = false
    @State private var result: ToolResult?
    @State private var error: String?

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _url = State(initialValue: initialFiles.first)
    }

    private let keys: [(String, String, String)] = [("title", "Title", "Tajuk"), ("author", "Author", "Pengarang"), ("subject", "Subject", "Subjek"),
                                                    ("keywords", "Keywords (comma separated)", "Kata kunci (dipisah koma)"), ("creator", "Creator app", "Aplikasi pencipta")]

    var body: some View {
        Group {
            if loaded, let u = url {
                ScrollView {
                    VStack(spacing: 16) {
                        FileRow(url: u, onDelete: { url = nil; loaded = false })
                            .padding(12).glass(18)
                        VStack(spacing: 12) {
                            ForEach(keys, id: \.0) { k in
                                OptionRow(title: L(k.1, k.2)) {
                                    TextField("", text: Binding(get: { fields[k.0] ?? "" }, set: { fields[k.0] = $0 })).fieldStyle()
                                }
                            }
                        }
                        .padding(16).glass(22)
                        if let e = error { ErrorBanner(text: e) }
                        RunButton(title: L("Save metadata", "Simpan metadata"), busy: false, progress: 0, enabled: true, action: save)
                        if let r = result { ResultsSection(result: r) }
                    }
                    .padding(16)
                }
                .background(AppBackground())
            } else {
                PickPDFPrompt(tool: tool) { url = $0 }
            }
        }
        .task(id: url) {
            guard let u = url else { return }
            fields = StampEngine.readMetadata(u)
            loaded = true
        }
    }

    private func save() {
        guard let u = url else { return }
        let out = Workspace.unique(Workspace.newDir("Out"), Workspace.base(u) + ".pdf")
        do { try StampEngine.writeMetadata(u, fields: fields, out: out); result = ToolResult(files: [out]); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
