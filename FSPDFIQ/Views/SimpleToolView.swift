import SwiftUI
import PDFKit

struct ToolHostView: View {
    let tool: Tool
    let initialFiles: [URL]

    var body: some View {
        Group {
            switch tool.id {
            case "workbench": PageBoardView(tool: tool, mode: .workbench, initialFiles: initialFiles)
            case "organize-pdf": PageBoardView(tool: tool, mode: .organize, initialFiles: initialFiles)
            case "remove-pages": PageSelectView(tool: tool, extract: false, initialFiles: initialFiles)
            case "extract-pages": PageSelectView(tool: tool, extract: true, initialFiles: initialFiles)
            case "reorder-pages": ReorderView(tool: tool, initialFiles: initialFiles)
            case "edit-pdf": EditorScreen(tool: tool, mode: .edit, initialFiles: initialFiles)
            case "sign-pdf": EditorScreen(tool: tool, mode: .sign, initialFiles: initialFiles)
            case "redact-pdf": EditorScreen(tool: tool, mode: .redact, initialFiles: initialFiles)
            case "crop-pdf": CropView(tool: tool, initialFiles: initialFiles)
            case "scan-to-pdf": ScanView(tool: tool)
            case "listen-pdf": ListenView(tool: tool, initialFiles: initialFiles)
            case "preview-pdf": PreviewScreen(tool: tool, initialFiles: initialFiles)
            case "pdf-to-ai": AIView(tool: tool, initialFiles: initialFiles)
            case "edit-metadata": MetadataView(tool: tool, initialFiles: initialFiles)
            default: SimpleToolView(tool: tool, initialFiles: initialFiles)
            }
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ToolOptions {
    var range = ""
    var splitMode = 0
    var splitEvery = 2
    var level = 1
    var useTarget = false
    var targetKB = 200
    var angle = 90
    var position = 4
    var numberFormat = 0
    var start = 1
    var fontSize: Double = 11
    var skipFirst = false
    var text = ""
    var suffix = ""
    var digits = 6
    var style = 0
    var colorIndex = 0
    var opacity: Double = 0.2
    var markSize: Double = 64
    var password = ""
    var password2 = ""
    var dpi = 150
    var quality: Double = 0.85
    var transparent = false
    var pageSize = 0
    var orientation = 0
    var margin: Double = 20
    var wordMode = 0
    var perSheet = 4
    var border = true
    var filterMode = 0
    var inkMode = 0
    var inkGray = false
    var slidesPerPage = 1
    var thesis: [Double] = [3.8, 2.5, 2.5, 2.5]
    var malay = true
    var oneSheet = false
    var millimetres = true
    var landscape = false
    var pasted = ""
}

struct SimpleToolView: View {
    let tool: Tool
    @State private var files: [URL]
    @State private var o = ToolOptions()
    @State private var busy = false
    @State private var progress = 0.0
    @State private var error: String? = nil
    @State private var result: ToolResult? = nil
    @State private var pageCount = 0

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _files = State(initialValue: initialFiles)
        var opts = ToolOptions()
        if tool.id == "bates-numbering" { opts.text = "ABC"; opts.position = 5; opts.fontSize = 10 }
        if tool.id == "watermark" { opts.text = L("CONFIDENTIAL", "SULIT") }
        if tool.id == "pdf-to-png" { opts.dpi = 200 }
        if tool.id == "excel-to-pdf" { opts.landscape = true }
        _o = State(initialValue: opts)
    }

    private var acceptsPaste: Bool { tool.input == .html || tool.input == .markdown }

    private var canRun: Bool {
        if acceptsPaste && !o.pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        switch tool.input {
        case .pdfs: return files.count >= 2
        case .twoPDFs: return files.count == 2
        default: return !files.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ToolHeader(tool: tool)
                FileInputSection(kind: tool.input, files: $files)
                if acceptsPaste { pasteBox }
                if canRun || !files.isEmpty { optionsCard }
                if let e = error { ErrorBanner(text: e) }
                RunButton(title: actionTitle, busy: busy, progress: progress, enabled: canRun && validOptions, action: run)
                if let r = result { ResultsSection(result: r) }
            }
            .padding(16)
        }
        .background(AppBackground())
        .onChange(of: files) { f in
            result = nil; error = nil
            pageCount = f.first.map { PDFIO.pageCount($0) } ?? 0
        }
        .onAppear { pageCount = files.first.map { PDFIO.pageCount($0) } ?? 0 }
    }

    private var actionTitle: String {
        switch tool.id {
        case "merge-pdf": return L("Merge PDFs", "Gabungkan PDF")
        case "split-pdf": return L("Split PDF", "Pisahkan PDF")
        case "compress-pdf": return L("Compress", "Mampatkan")
        case "protect-pdf": return L("Protect with password", "Lindungi dengan kata laluan")
        case "unlock-pdf": return L("Unlock", "Buka kunci")
        case "compare-pdf": return L("Compare", "Bandingkan")
        case "ocr-pdf": return L("Recognise text", "Kenal pasti teks")
        default: return L("Convert", "Tukar") + " ▸"
        }
    }

    private var validOptions: Bool {
        if tool.id == "protect-pdf" { return o.password.count >= 4 && o.password == o.password2 }
        return true
    }

    // MARK: Paste box

    private var pasteBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: tool.input == .html ? L("Or paste HTML", "Atau tampal HTML") : L("Or paste Markdown", "Atau tampal Markdown"))
            TextEditor(text: $o.pasted)
                .font(.footnote.monospaced())
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .fieldStyle()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(16)
        .glass(22)
    }

    // MARK: Options

    @ViewBuilder private var optionsCard: some View {
        let content = optionsContent
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: L("Options", "Pilihan"))
            content
        }
        .padding(16)
        .glass(22)
    }

    private var rangeField: some View {
        OptionRow(title: L("Pages", "Halaman") + (pageCount > 0 ? " (1–\(pageCount))" : "")) {
            TextField(L("All pages — or e.g. 1-3, 5", "Semua halaman — atau cth. 1-3, 5"), text: $o.range)
                .keyboardType(.numbersAndPunctuation)
                .fieldStyle()
        }
    }

    private var positionPicker: some View {
        OptionRow(title: L("Position", "Kedudukan")) {
            Picker("", selection: $o.position) {
                Text(L("Top left", "Atas kiri")).tag(0)
                Text(L("Top centre", "Atas tengah")).tag(1)
                Text(L("Top right", "Atas kanan")).tag(2)
                Text(L("Bottom left", "Bawah kiri")).tag(3)
                Text(L("Bottom centre", "Bawah tengah")).tag(4)
                Text(L("Bottom right", "Bawah kanan")).tag(5)
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder private var optionsContent: some View {
        switch tool.id {
        case "merge-pdf":
            Text(L("Files are merged top to bottom. Use the arrows to change the order.",
                   "Fail digabung dari atas ke bawah. Guna anak panah untuk ubah susunan.")).font(.footnote).foregroundColor(.secondary)
        case "split-pdf":
            Picker("", selection: $o.splitMode) {
                Text(L("Every page", "Setiap halaman")).tag(0)
                Text(L("Ranges", "Julat")).tag(1)
                Text(L("Every N", "Setiap N")).tag(2)
            }.pickerStyle(.segmented)
            if o.splitMode == 1 {
                OptionRow(title: L("Each comma group becomes a file", "Setiap kumpulan berkoma menjadi satu fail")) {
                    TextField("1-3, 4-6, 7", text: $o.range).keyboardType(.numbersAndPunctuation).fieldStyle()
                }
            } else if o.splitMode == 2 {
                Stepper(L("Every \(o.splitEvery) pages", "Setiap \(o.splitEvery) halaman"), value: $o.splitEvery, in: 1...500)
            }
        case "compress-pdf":
            Toggle(L("Aim for a target size", "Sasarkan saiz tertentu"), isOn: $o.useTarget).tint(.fsTeal)
            if o.useTarget {
                Picker("", selection: $o.targetKB) {
                    ForEach([100, 200, 300, 500, 1000, 2000], id: \.self) { kb in Text(kb >= 1000 ? "\(kb / 1000) MB" : "\(kb) KB").tag(kb) }
                }.pickerStyle(.segmented)
            } else {
                Picker("", selection: $o.level) {
                    Text(L("Light", "Ringan")).tag(0)
                    Text(L("Balanced", "Seimbang")).tag(1)
                    Text(L("Strong", "Kuat")).tag(2)
                }.pickerStyle(.segmented)
            }
            Text(L("Pages are re-saved as images, so text is no longer selectable.",
                   "Halaman disimpan semula sebagai imej, jadi teks tidak lagi boleh dipilih.")).font(.caption).foregroundColor(.secondary)
        case "rotate-pdf":
            Picker("", selection: $o.angle) {
                Text("90° ↻").tag(90); Text("180°").tag(180); Text("270° ↺").tag(270)
            }.pickerStyle(.segmented)
            rangeField
        case "page-numbers":
            positionPicker
            OptionRow(title: L("Format", "Format")) {
                Picker("", selection: $o.numberFormat) {
                    Text("1").tag(0)
                    Text(L("Page 1 of N", "Halaman 1 daripada N")).tag(1)
                    Text("1 / N").tag(2)
                    Text("- 1 -").tag(3)
                }.pickerStyle(.menu)
            }
            Stepper(L("Start at \(o.start)", "Mula dari \(o.start)"), value: $o.start, in: 0...9999)
            Stepper(L("Font size \(Int(o.fontSize))", "Saiz fon \(Int(o.fontSize))"), value: $o.fontSize, in: 6...28)
            Toggle(L("Skip the cover page", "Langkau halaman muka depan"), isOn: $o.skipFirst).tint(.fsTeal)
        case "bates-numbering":
            HStack {
                OptionRow(title: L("Prefix", "Awalan")) { TextField("ABC", text: $o.text).fieldStyle() }
                OptionRow(title: L("Suffix", "Akhiran")) { TextField("", text: $o.suffix).fieldStyle() }
            }
            Stepper(L("Start at \(o.start)", "Mula dari \(o.start)"), value: $o.start, in: 0...999_999)
            Stepper(L("Digits: \(o.digits)", "Digit: \(o.digits)"), value: $o.digits, in: 1...10)
            positionPicker
            Text(L("Preview: ", "Pratonton: ") + o.text + String(repeating: "0", count: max(0, o.digits - String(o.start).count)) + "\(o.start)" + o.suffix)
                .font(.footnote.monospaced()).foregroundColor(.fsTeal)
        case "watermark":
            OptionRow(title: L("Text", "Teks")) { TextField(L("CONFIDENTIAL", "SULIT"), text: $o.text).fieldStyle() }
            Picker("", selection: $o.style) {
                Text(L("Diagonal", "Pepenjuru")).tag(0); Text(L("Centre", "Tengah")).tag(1); Text(L("Tiled", "Berjubin")).tag(2)
            }.pickerStyle(.segmented)
            OptionRow(title: L("Colour", "Warna")) {
                HStack(spacing: 12) {
                    ForEach(0..<StampEngine.colors.count, id: \.self) { i in
                        Circle().fill(Color(StampEngine.colors[i])).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(o.colorIndex == i ? 0.8 : 0), lineWidth: 2.5).padding(-4))
                            .onTapGesture { o.colorIndex = i }
                    }
                }
            }
            OptionRow(title: L("Opacity \(Int(o.opacity * 100))%", "Kelegapan \(Int(o.opacity * 100))%")) { Slider(value: $o.opacity, in: 0.05...0.8).tint(.fsTeal) }
            OptionRow(title: L("Size \(Int(o.markSize))", "Saiz \(Int(o.markSize))")) { Slider(value: $o.markSize, in: 18...140).tint(.fsTeal) }
            rangeField
        case "protect-pdf":
            SecureField(L("Password (min 4 characters)", "Kata laluan (min 4 aksara)"), text: $o.password).fieldStyle()
            SecureField(L("Confirm password", "Sahkan kata laluan"), text: $o.password2).fieldStyle()
            if !o.password2.isEmpty && o.password != o.password2 {
                Text(L("Passwords don't match.", "Kata laluan tidak sepadan.")).font(.caption).foregroundColor(.fsRed)
            }
            Text(L("Keep the password safe — it can't be recovered.", "Simpan kata laluan dengan selamat — ia tidak boleh dipulihkan."))
                .font(.caption).foregroundColor(.secondary)
        case "unlock-pdf":
            SecureField(L("Current password (leave empty if it opens without one)", "Kata laluan semasa (kosongkan jika dibuka tanpa kata laluan)"), text: $o.password).fieldStyle()
        case "pdf-to-jpg":
            Picker("", selection: $o.dpi) { Text(L("Screen", "Skrin")).tag(96); Text(L("Standard", "Standard")).tag(150); Text(L("High", "Tinggi")).tag(300) }.pickerStyle(.segmented)
            OptionRow(title: L("Quality \(Int(o.quality * 100))%", "Kualiti \(Int(o.quality * 100))%")) { Slider(value: $o.quality, in: 0.4...1).tint(.fsTeal) }
            rangeField
        case "pdf-to-png":
            Picker("", selection: $o.dpi) { Text("96 DPI").tag(96); Text("200 DPI").tag(200); Text("300 DPI").tag(300) }.pickerStyle(.segmented)
            Toggle(L("Transparent background", "Latar lutsinar"), isOn: $o.transparent).tint(.fsTeal)
            rangeField
        case "jpg-to-pdf":
            Picker("", selection: $o.pageSize) { Text("A4").tag(0); Text("Letter").tag(1); Text(L("Fit image", "Ikut imej")).tag(2) }.pickerStyle(.segmented)
            if o.pageSize != 2 {
                Picker("", selection: $o.orientation) { Text(L("Auto", "Auto")).tag(0); Text(L("Portrait", "Potret")).tag(1); Text(L("Landscape", "Landskap")).tag(2) }.pickerStyle(.segmented)
                OptionRow(title: L("Margin \(Int(o.margin)) pt", "Margin \(Int(o.margin)) pt")) { Slider(value: $o.margin, in: 0...72).tint(.fsTeal) }
            }
        case "pdf-to-word":
            Picker("", selection: $o.wordMode) { Text(L("Editable text", "Teks boleh sunting")).tag(0); Text(L("Exact layout", "Susun atur tepat")).tag(1) }.pickerStyle(.segmented)
            Text(o.wordMode == 0 ? L("Best for editing. Paragraphs are rebuilt; complex layouts may shift.", "Terbaik untuk menyunting. Perenggan dibina semula; susun atur kompleks mungkin berubah.")
                                 : L("Looks identical, but each page is a picture in Word.", "Kelihatan sama, tetapi setiap halaman ialah gambar dalam Word."))
                .font(.caption).foregroundColor(.secondary)
        case "pdf-to-excel":
            Toggle(L("Put all pages on one sheet", "Letak semua halaman dalam satu helaian"), isOn: $o.oneSheet).tint(.fsTeal)
            Text(L("Works best with PDFs that have selectable text, such as e-statements.", "Paling sesuai untuk PDF yang mempunyai teks boleh pilih, seperti e-penyata."))
                .font(.caption).foregroundColor(.secondary)
        case "excel-to-pdf":
            Toggle(L("Landscape pages", "Halaman landskap"), isOn: $o.landscape).tint(.fsTeal)
        case "html-to-pdf", "markdown-to-pdf":
            Toggle(L("Landscape pages", "Halaman landskap"), isOn: $o.landscape).tint(.fsTeal)
        case "n-up-pdf":
            Picker("", selection: $o.perSheet) { ForEach([2, 4, 6, 9, 16], id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
            Toggle(L("Draw page borders", "Lukis sempadan halaman"), isOn: $o.border).tint(.fsTeal)
        case "booklet-pdf":
            Text(L("Print double-sided, flip on the short edge, then fold in half.", "Cetak dua muka, terbalik pada sisi pendek, kemudian lipat dua."))
                .font(.footnote).foregroundColor(.secondary)
        case "magic-filter":
            Picker("", selection: $o.filterMode) {
                Text(L("Magic", "Ajaib")).tag(0); Text(L("B&W", "H&P")).tag(1); Text(L("Gray", "Kelabu")).tag(2); Text(L("Original", "Asal")).tag(3)
            }.pickerStyle(.segmented)
        case "slide-ink-saver":
            Picker("", selection: $o.inkMode) { Text(L("Dark slides only", "Slaid gelap sahaja")).tag(0); Text(L("Invert all", "Songsang semua")).tag(1) }.pickerStyle(.segmented)
            Toggle(L("Also remove colour", "Juga buang warna"), isOn: $o.inkGray).tint(.fsTeal)
        case "thesis-margin":
            HStack {
                Button("UiTM / UKM") { o.thesis = [3.8, 2.5, 2.5, 2.5] }.buttonStyle(SoftButtonStyle())
                Button("UTM / UM") { o.thesis = [4.0, 2.5, 2.5, 2.5] }.buttonStyle(SoftButtonStyle())
            }
            ForEach(0..<4, id: \.self) { i in
                let names = [L("Left", "Kiri"), L("Top", "Atas"), L("Right", "Kanan"), L("Bottom", "Bawah")]
                Stepper(names[i] + String(format: ": %.1f cm", o.thesis[i]), value: $o.thesis[i], in: 0...6, step: 0.1)
            }
            Text(L("Always check your faculty's latest format guide.", "Sentiasa semak panduan format terkini fakulti anda.")).font(.caption).foregroundColor(.secondary)
        case "cornell-notes":
            Picker("", selection: $o.slidesPerPage) { Text(L("1 slide per page", "1 slaid sehalaman")).tag(1); Text(L("2 slides per page", "2 slaid sehalaman")).tag(2) }.pickerStyle(.segmented)
        case "ocr-pdf":
            Toggle(L("Document is in Bahasa Melayu", "Dokumen dalam Bahasa Melayu"), isOn: $o.malay).tint(.fsTeal)
        case "pdf-to-dwg":
            Picker("", selection: $o.millimetres) { Text(L("Millimetres", "Milimeter")).tag(true); Text(L("Points", "Mata")).tag(false) }.pickerStyle(.segmented)
            Text(L("Exports DXF, which opens in AutoCAD, DraftSight and LibreCAD. DWG is a closed format — save as DWG from AutoCAD if needed.",
                   "Mengeksport DXF yang boleh dibuka dalam AutoCAD, DraftSight dan LibreCAD. DWG ialah format tertutup — simpan sebagai DWG dari AutoCAD jika perlu."))
                .font(.caption).foregroundColor(.secondary)
        case "pdf-to-pdfa":
            Text(L("Creates PDF/A-2b. Pages are stored as high-quality images so they look the same everywhere; run OCR first if you need searchable text.",
                   "Menghasilkan PDF/A-2b. Halaman disimpan sebagai imej berkualiti tinggi supaya kelihatan sama di mana-mana; jalankan OCR dahulu jika perlukan teks boleh dicari."))
                .font(.caption).foregroundColor(.secondary)
        default:
            Text(L("Ready when you are.", "Sedia apabila anda sedia.")).font(.footnote).foregroundColor(.secondary)
        }
    }

    // MARK: Run

    private func run() {
        error = nil
        result = nil
        busy = true
        progress = 0
        let tool = self.tool, files = self.files, o = self.o
        let outDir = Workspace.newDir("Out")
        let report: Progress = { p in DispatchQueue.main.async { self.progress = p } }

        Task {
            do {
                let r: ToolResult
                switch tool.input {
                case .word, .excel, .powerpoint, .html, .markdown:
                    r = try await runDocument(tool: tool, files: files, o: o, outDir: outDir, report: report)
                default:
                    r = try await Task.detached(priority: .userInitiated) {
                        try SimpleToolView.runPDF(tool: tool, files: files, o: o, outDir: outDir, report: report)
                    }.value
                }
                await MainActor.run { result = r; busy = false; progress = 1 }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; busy = false }
            }
        }
    }

    @MainActor
    private func runDocument(tool: Tool, files: [URL], o: ToolOptions, outDir: URL, report: @escaping Progress) async throws -> ToolResult {
        let src = files.first
        let base = src.map { Workspace.base($0) } ?? (tool.input == .html ? "page" : "notes")
        var data: Data
        switch tool.id {
        case "word-to-pdf":
            guard let u = src else { throw IQError.noInput }
            switch u.pathExtension.lowercased() {
            case "docx": data = try await WebPDF.render(html: try OfficeImport.docxToHTML(try Data(contentsOf: u)))
            case "rtf", "txt": data = try OfficeImport.textToPDF(u)
            default: data = try await WebPDF.render(fileURL: u)
            }
        case "excel-to-pdf":
            guard let u = src else { throw IQError.noInput }
            switch u.pathExtension.lowercased() {
            case "xlsx": data = try await WebPDF.render(html: try OfficeImport.xlsxToHTML(try Data(contentsOf: u)), landscape: o.landscape, margin: 24)
            case "csv":
                let text = (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1)) ?? ""
                data = try await WebPDF.render(html: OfficeImport.csvToHTML(text), landscape: o.landscape, margin: 24)
            default: data = try await WebPDF.render(fileURL: u, landscape: o.landscape)
            }
        case "pptx-to-pdf":
            guard let u = src else { throw IQError.noInput }
            if u.pathExtension.lowercased() == "pptx" {
                let d = try Data(contentsOf: u)
                data = try await Task.detached(priority: .userInitiated) { try PptxRenderer.render(d, progress: report) }.value
            } else {
                data = try await WebPDF.render(fileURL: u, landscape: true)
            }
        case "html-to-pdf":
            if let u = src {
                data = try await WebPDF.render(fileURL: u, landscape: o.landscape)
            } else {
                data = try await WebPDF.render(html: o.pasted, landscape: o.landscape)
            }
        case "markdown-to-pdf":
            let md = src.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? o.pasted
            data = try await WebPDF.render(html: OfficeImport.markdownToHTML(md), landscape: o.landscape, margin: 48)
        default:
            throw IQError.noInput
        }
        let out = Workspace.unique(outDir, base + ".pdf")
        try data.write(to: out)
        let pages = PDFDocument(data: data)?.pageCount ?? 0
        return ToolResult(files: [out], message: L("\(pages) page(s) created.", "\(pages) halaman dihasilkan."))
    }

    static func runPDF(tool: Tool, files: [URL], o: ToolOptions, outDir: URL, report: @escaping Progress) throws -> ToolResult {
        guard let src = files.first else { throw IQError.noInput }
        let base = Workspace.base(src)
        func out(_ suffix: String, _ ext: String = "pdf") -> URL { Workspace.unique(outDir, "\(base)\(suffix).\(ext)") }

        switch tool.id {
        case "merge-pdf":
            let u = Workspace.unique(outDir, "merged.pdf")
            try OrganizeEngine.merge(files, out: u, progress: report)
            return ToolResult(files: [u], message: L("\(files.count) files merged.", "\(files.count) fail digabungkan."))
        case "split-pdf":
            let outs = try OrganizeEngine.split(src, mode: o.splitMode, ranges: o.range, every: o.splitEvery, outDir: outDir)
            return ToolResult(files: try withZip(outs, outDir: outDir, name: base + "_split"), message: L("\(outs.count) files created.", "\(outs.count) fail dihasilkan."))
        case "compress-pdf":
            let u = out("_compressed")
            let msg = try OptimizeEngine.compress(src, level: o.level, targetKB: o.useTarget ? o.targetKB : nil, out: u, progress: report)
            return ToolResult(files: [u], message: msg)
        case "rotate-pdf":
            let u = out("_rotated"); try OrganizeEngine.rotate(src, angle: o.angle, range: o.range, out: u)
            return ToolResult(files: [u])
        case "booklet-pdf":
            let u = out("_booklet"); try OrganizeEngine.booklet(src, out: u); return ToolResult(files: [u])
        case "n-up-pdf":
            let u = out("_\(o.perSheet)up"); try OrganizeEngine.nUp(src, perSheet: o.perSheet, border: o.border, out: u); return ToolResult(files: [u])
        case "pdf-to-grayscale":
            let u = out("_grayscale"); try OptimizeEngine.grayscale(src, out: u, progress: report); return ToolResult(files: [u])
        case "repair-pdf":
            let u = out("_repaired"); let m = try OptimizeEngine.repair(src, out: u); return ToolResult(files: [u], message: m)
        case "flatten-pdf":
            let u = out("_flattened"); try OptimizeEngine.flatten(src, out: u); return ToolResult(files: [u])
        case "pdf-to-pdfa":
            let u = out("_PDFA"); try OptimizeEngine.pdfa(src, out: u, progress: report)
            return ToolResult(files: [u], message: L("Saved as PDF/A-2b.", "Disimpan sebagai PDF/A-2b."))
        case "magic-filter":
            let u = out("_enhanced"); try OptimizeEngine.magic(files, mode: o.filterMode, out: u, progress: report); return ToolResult(files: [u])
        case "slide-ink-saver":
            let u = out("_inksaver"); try OptimizeEngine.inkSaver(src, mode: o.inkMode, grayscale: o.inkGray, out: u, progress: report); return ToolResult(files: [u])
        case "thesis-margin":
            let u = out("_margins"); try OptimizeEngine.thesis(src, marginsCM: o.thesis, out: u); return ToolResult(files: [u])
        case "cornell-notes":
            let u = out("_cornell"); try OptimizeEngine.cornell(src, perPage: o.slidesPerPage, out: u); return ToolResult(files: [u])
        case "ocr-pdf":
            let r = try OCREngine.run(files, malay: o.malay, outDir: outDir, progress: report)
            return ToolResult(files: [r.pdf, r.txt], message: L("\(r.chars) characters recognised. The PDF is now searchable.", "\(r.chars) aksara dikenal pasti. PDF kini boleh dicari."),
                              preview: try? String(contentsOf: r.txt, encoding: .utf8))
        case "jpg-to-pdf":
            let u = Workspace.unique(outDir, (files.count == 1 ? base : "images") + ".pdf")
            try ConvertEngine.imagesToPDF(files, pageSize: o.pageSize, orientation: o.orientation, margin: CGFloat(o.margin), out: u, progress: report)
            return ToolResult(files: [u], message: L("\(files.count) image(s) converted.", "\(files.count) imej ditukar."))
        case "pdf-to-jpg", "pdf-to-png":
            let png = tool.id == "pdf-to-png"
            let outs = try ConvertEngine.pdfToImages(src, png: png, dpi: CGFloat(o.dpi), quality: CGFloat(o.quality), transparent: o.transparent,
                                                     range: o.range, outDir: outDir, progress: report)
            return ToolResult(files: try withZip(outs, outDir: outDir, name: base + (png ? "_png" : "_jpg")),
                              message: L("\(outs.count) image(s) created.", "\(outs.count) imej dihasilkan."))
        case "pdf-to-text":
            let u = out("", "txt"); let t = try ConvertEngine.pdfToText(src, out: u)
            return ToolResult(files: [u], preview: t)
        case "pdf-to-word":
            let u = out("", "docx"); try ConvertEngine.pdfToWord(src, mode: o.wordMode, out: u, progress: report); return ToolResult(files: [u])
        case "pdf-to-excel":
            let outs = try ConvertEngine.pdfToExcel(src, oneSheet: o.oneSheet, outDir: outDir, progress: report)
            return ToolResult(files: outs, message: L("Check the columns — complex tables may need small fixes.", "Semak lajur — jadual kompleks mungkin perlu sedikit pembetulan."))
        case "pdf-to-pptx":
            let u = out("", "pptx"); try ConvertEngine.pdfToPPTX(src, out: u, progress: report); return ToolResult(files: [u])
        case "pdf-to-dwg":
            let outs = try ConvertEngine.pdfToDXF(src, millimetres: o.millimetres, outDir: outDir, progress: report)
            return ToolResult(files: try withZip(outs, outDir: outDir, name: base + "_dxf"))
        case "extract-images":
            let outs = try ConvertEngine.extractImages(src, outDir: outDir, progress: report)
            return ToolResult(files: try withZip(outs, outDir: outDir, name: base + "_images"),
                              message: L("\(outs.count) image(s) found.", "\(outs.count) imej ditemui."))
        case "page-numbers":
            let u = out("_numbered")
            try StampEngine.pageNumbers(src, position: o.position, format: o.numberFormat, start: o.start, fontSize: CGFloat(o.fontSize), skipFirst: o.skipFirst, out: u)
            return ToolResult(files: [u])
        case "bates-numbering":
            let u = out("_bates")
            try StampEngine.bates(src, prefix: o.text, suffix: o.suffix, start: o.start, digits: o.digits, position: o.position, fontSize: CGFloat(o.fontSize), out: u)
            return ToolResult(files: [u])
        case "watermark":
            let u = out("_watermarked")
            try StampEngine.watermark(src, text: o.text, style: o.style, colorIndex: o.colorIndex, opacity: CGFloat(o.opacity), fontSize: CGFloat(o.markSize), range: o.range, out: u)
            return ToolResult(files: [u])
        case "protect-pdf":
            let u = out("_protected"); try StampEngine.protect(src, password: o.password, out: u)
            return ToolResult(files: [u], message: L("Protected. You'll need the password to open it.", "Dilindungi. Anda perlukan kata laluan untuk membukanya."))
        case "unlock-pdf":
            let u = out("_unlocked"); try StampEngine.unlock(src, password: o.password, out: u); return ToolResult(files: [u])
        case "compare-pdf":
            guard files.count == 2 else { throw IQError.noInput }
            let u = Workspace.unique(outDir, "compare.pdf")
            let m = try CompareEngine.compare(files[0], files[1], out: u, progress: report)
            return ToolResult(files: [u], message: m)
        default:
            throw IQError.msg("This tool isn't available yet.", "Alat ini belum tersedia.")
        }
    }

    /// Adds a .zip when several files are produced.
    static func withZip(_ outs: [URL], outDir: URL, name: String) throws -> [URL] {
        guard outs.count > 1 else { return outs }
        let z = Workspace.unique(outDir, name + ".zip")
        try ZipWriter.zip(files: outs, to: z)
        return [z] + outs
    }
}
