import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Shared "pick one PDF" prompt

struct PickPDFPrompt: View {
    let tool: Tool
    let onPick: (URL) -> Void
    @State private var files: [URL] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ToolHeader(tool: tool)
                FileInputSection(kind: .pdf, files: $files)
            }
            .padding(16)
        }
        .background(AppBackground())
        .onChange(of: files) { f in if let u = f.first { onPick(u) } }
    }
}

// MARK: - Remove / Extract pages

struct PageSelectView: View {
    let tool: Tool
    let extract: Bool
    @State private var url: URL?
    @State private var doc: PDFDocument?
    @State private var selected = Set<Int>()
    @State private var rangeText = ""
    @State private var result: ToolResult?
    @State private var error: String?
    @State private var busy = false

    init(tool: Tool, extract: Bool, initialFiles: [URL]) {
        self.tool = tool
        self.extract = extract
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if let d = doc {
                ScrollView {
                    VStack(spacing: 14) {
                        Text(extract ? L("Tap the pages to keep in the new PDF.", "Ketik halaman yang ingin dimasukkan ke PDF baharu.")
                                     : L("Tap the pages to delete.", "Ketik halaman yang ingin dipadam."))
                            .font(.subheadline).foregroundColor(.secondary)
                        HStack {
                            TextField(L("Select by range, e.g. 2-4, 7", "Pilih ikut julat, cth. 2-4, 7"), text: $rangeText)
                                .keyboardType(.numbersAndPunctuation).fieldStyle()
                            Button(L("Select", "Pilih")) {
                                if let idx = try? PDFIO.parseRange(rangeText, count: d.pageCount) { selected = Set(idx) }
                            }.buttonStyle(SoftButtonStyle())
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                            ForEach(0..<d.pageCount, id: \.self) { i in
                                let on = selected.contains(i)
                                VStack(spacing: 4) {
                                    PageThumb(page: d.page(at: i), size: CGSize(width: 96, height: 128))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? (extract ? Color.fsTeal : Color.fsRed) : Color.clear, lineWidth: 3))
                                        .overlay(alignment: .topTrailing) {
                                            if on {
                                                Image(systemName: extract ? "checkmark.circle.fill" : "trash.circle.fill")
                                                    .foregroundColor(extract ? .fsTeal : .fsRed).font(.title3).background(Circle().fill(.white)).padding(4)
                                            }
                                        }
                                        .opacity(!extract && on ? 0.55 : 1)
                                    Text("\(i + 1)").font(.caption.weight(.semibold))
                                }
                                .onTapGesture { if on { selected.remove(i) } else { selected.insert(i) } }
                            }
                        }
                        if let e = error { ErrorBanner(text: e) }
                        RunButton(title: extract ? L("Extract \(selected.count) page(s)", "Ekstrak \(selected.count) halaman")
                                                 : L("Remove \(selected.count) page(s)", "Buang \(selected.count) halaman"),
                                  busy: busy, progress: 0, enabled: !selected.isEmpty, action: run)
                        if let r = result { ResultsSection(result: r) }
                    }
                    .padding(16)
                }
                .background(AppBackground())
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(selected.count == d.pageCount ? L("None", "Tiada") : L("All", "Semua")) {
                            selected = selected.count == d.pageCount ? [] : Set(0..<d.pageCount)
                        }
                    }
                }
            } else {
                PickPDFPrompt(tool: tool) { url = $0 }
            }
        }
        .task(id: url) { load() }
    }

    private func load() {
        guard let u = url else { return }
        do { doc = try PDFIO.open(u); error = nil } catch { self.error = error.localizedDescription; url = nil }
    }

    private func run() {
        guard let u = url else { return }
        busy = true; error = nil
        let out = Workspace.unique(Workspace.newDir("Out"), Workspace.base(u) + (extract ? "_extracted.pdf" : "_edited.pdf"))
        do {
            if extract { try OrganizeEngine.subset(u, indices: selected.sorted(), out: out) }
            else { try OrganizeEngine.remove(u, indices: selected, out: out) }
            result = ToolResult(files: [out])
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}

// MARK: - Reorder

struct ReorderView: View {
    let tool: Tool
    @State private var url: URL?
    @State private var doc: PDFDocument?
    @State private var order: [Int] = []
    @State private var result: ToolResult?
    @State private var error: String?

    init(tool: Tool, initialFiles: [URL]) {
        self.tool = tool
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if let d = doc {
                List {
                    Section {
                        ForEach(order, id: \.self) { i in
                            HStack(spacing: 14) {
                                PageThumb(page: d.page(at: i), size: CGSize(width: 54, height: 72))
                                Text(L("Page \(i + 1)", "Halaman \(i + 1)")).font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                        .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text(L("Drag the handles to reorder", "Seret pemegang untuk susun semula"))
                    }
                    Section {
                        Button(L("Reverse order", "Terbalikkan susunan")) { order.reverse() }
                        Button(L("Reset", "Set semula")) { order = Array(0..<d.pageCount) }
                        Button(L("Save new order", "Simpan susunan baharu")) { save() }.font(.headline).foregroundColor(.fsRed)
                    }
                    if let e = error { Section { Text(e).foregroundColor(.fsRed) } }
                    if let r = result { Section { ResultsSection(result: r).listRowInsets(EdgeInsets()) } }
                }
                .environment(\.editMode, .constant(.active))
            } else {
                PickPDFPrompt(tool: tool) { url = $0 }
            }
        }
        .task(id: url) {
            guard let u = url else { return }
            do { let d = try PDFIO.open(u); doc = d; order = Array(0..<d.pageCount) } catch { self.error = error.localizedDescription; url = nil }
        }
    }

    private func save() {
        guard let u = url else { return }
        let out = Workspace.unique(Workspace.newDir("Out"), Workspace.base(u) + "_reordered.pdf")
        do { try OrganizeEngine.subset(u, indices: order, out: out); result = ToolResult(files: [out]) }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Organize & Workbench

final class BoardModel: ObservableObject {
    @Published var doc: PDFDocument
    @Published var version = 0
    @Published var selected: Set<Int> = []
    let name: String
    private var undoStack: [Data] = []
    private var redoStack: [Data] = []

    init(doc: PDFDocument, name: String) {
        self.doc = doc
        self.name = name
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() -> Data? { doc.dataRepresentation() }

    func change(_ body: (PDFDocument) -> Void) {
        if let s = snapshot() { undoStack.append(s); if undoStack.count > 30 { undoStack.removeFirst() } }
        redoStack.removeAll()
        body(doc)
        refresh()
    }

    func replace(with data: Data) {
        guard let d = PDFDocument(data: data) else { return }
        if let s = snapshot() { undoStack.append(s) }
        redoStack.removeAll()
        doc = d
        selected = []
        refresh()
    }

    func undo() {
        guard let last = undoStack.popLast(), let d = PDFDocument(data: last) else { return }
        if let s = snapshot() { redoStack.append(s) }
        doc = d; selected = []; refresh()
    }

    func redo() {
        guard let next = redoStack.popLast(), let d = PDFDocument(data: next) else { return }
        if let s = snapshot() { undoStack.append(s) }
        doc = d; selected = []; refresh()
    }

    func refresh() { version += 1 }

    /// Writes the current document to a temp file (for tools that work on files).
    func tempFile() throws -> URL {
        let u = Workspace.unique(Workspace.newDir("Work"), name + ".pdf")
        guard let d = doc.dataRepresentation() else { throw IQError.saveFailed }
        try d.write(to: u)
        return u
    }

    func rotate(_ i: Int, by deg: Int) { change { $0.page(at: i)?.rotation = (($0.page(at: i)?.rotation ?? 0) + deg + 360) % 360 } }
    func delete(_ set: Set<Int>) {
        change { d in for i in set.sorted(by: >) where d.pageCount > 1 { d.removePage(at: i) } }
        selected = []
    }
    func duplicate(_ i: Int) { change { d in if let p = d.page(at: i)?.copy() as? PDFPage { d.insert(p, at: i + 1) } } }
    func blank(after i: Int) {
        change { d in
            let p = PDFPage()
            let size = d.page(at: i)?.bounds(for: .mediaBox).size ?? Paper.a4
            p.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
            d.insert(p, at: i + 1)
        }
    }
    func move(_ i: Int, by delta: Int) {
        let j = i + delta
        guard j >= 0, j < doc.pageCount else { return }
        change { $0.exchangePage(at: i, withPageAt: j) }
        if selected.contains(i) { selected.remove(i); selected.insert(j) }
    }
    func append(_ url: URL) throws {
        let other = try PDFIO.open(url)
        change { d in OrganizeEngine.copyPages(from: other, indices: Array(0..<other.pageCount), into: d) }
    }
}

struct PageBoardView: View {
    enum Mode { case organize, workbench }
    let tool: Tool
    let mode: Mode
    @State private var url: URL?
    @StateObject private var holder = BoardHolder()

    init(tool: Tool, mode: Mode, initialFiles: [URL]) {
        self.tool = tool
        self.mode = mode
        _url = State(initialValue: initialFiles.first)
    }

    var body: some View {
        Group {
            if let m = holder.model {
                BoardContent(model: m, mode: mode)
            } else {
                PickPDFPrompt(tool: tool) { url = $0 }
            }
        }
        .task(id: url) {
            guard let u = url, holder.model == nil else { return }
            if let d = try? PDFIO.open(u) { holder.model = BoardModel(doc: d, name: Workspace.base(u)) }
        }
    }
}

final class BoardHolder: ObservableObject { @Published var model: BoardModel? }

struct BoardContent: View {
    @ObservedObject var model: BoardModel
    let mode: PageBoardView.Mode
    @State private var result: ToolResult?
    @State private var error: String?
    @State private var busy = false
    @State private var showAdd = false
    @State private var prompt: WorkPrompt?
    @State private var promptText = ""
    @State private var showEditor = false

    enum WorkPrompt: Identifiable { case watermark, protect; var id: Int { self == .watermark ? 0 : 1 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text(L("\(model.doc.pageCount) pages", "\(model.doc.pageCount) halaman")).font(.subheadline.weight(.semibold))
                    if !model.selected.isEmpty {
                        Text("• " + L("\(model.selected.count) selected", "\(model.selected.count) dipilih")).font(.subheadline).foregroundColor(.fsTeal)
                    }
                    Spacer()
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo)
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo)
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 16) {
                    ForEach(0..<model.doc.pageCount, id: \.self) { i in
                        pageCell(i)
                    }
                }

                if !model.selected.isEmpty { selectionBar }
                if let e = error { ErrorBanner(text: e) }
                if busy { ProgressView().padding() }
                Button { export() } label: { Label(L("Save PDF", "Simpan PDF"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(PrimaryButtonStyle())
                if let r = result { ResultsSection(result: r) }
            }
            .padding(16)
        }
        .background(AppBackground())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showAdd = true } label: { Label(L("Add pages from PDF", "Tambah halaman daripada PDF"), systemImage: "plus.rectangle.on.rectangle") }
                    if mode == .workbench {
                        Divider()
                        Button { showEditor = true } label: { Label(L("Edit / sign pages", "Sunting / tandatangan"), systemImage: "pencil.tip.crop.circle") }
                        Button { apply { u, o in try StampEngine.pageNumbers(u, position: 4, format: 0, start: 1, fontSize: 11, skipFirst: false, out: o) } } label: {
                            Label(L("Add page numbers", "Tambah nombor halaman"), systemImage: "number")
                        }
                        Button { promptText = L("CONFIDENTIAL", "SULIT"); prompt = .watermark } label: { Label(L("Add watermark", "Tambah tera air"), systemImage: "seal") }
                        Button { apply { u, o in _ = try OptimizeEngine.compress(u, level: 1, targetKB: nil, out: o, progress: nil) } } label: {
                            Label(L("Compress", "Mampatkan"), systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        Button { apply { u, o in try OptimizeEngine.grayscale(u, out: o, progress: nil) } } label: { Label(L("Grayscale", "Skala kelabu"), systemImage: "circle.lefthalf.filled") }
                        Button { apply { u, o in try OptimizeEngine.flatten(u, out: o) } } label: { Label(L("Flatten", "Ratakan"), systemImage: "square.stack.3d.down.right") }
                        Divider()
                        Button { promptText = ""; prompt = .protect } label: { Label(L("Protect & save", "Lindungi & simpan"), systemImage: "lock") }
                    }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
        }
        .fileImporter(isPresented: $showAdd, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r {
                for u in Workspace.importCopies(urls) { do { try model.append(u) } catch { self.error = error.localizedDescription } }
            }
        }
        .alert(prompt == .protect ? L("Password", "Kata laluan") : L("Watermark text", "Teks tera air"),
               isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            if prompt == .protect { SecureField(L("Password", "Kata laluan"), text: $promptText) } else { TextField("", text: $promptText) }
            Button(L("Cancel", "Batal"), role: .cancel) { prompt = nil }
            Button("OK") { handlePrompt() }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                if let u = try? model.tempFile() {
                    EditorScreen(tool: Catalog.tool("edit-pdf")!, mode: .edit, initialFiles: [u]) { data in
                        model.replace(with: data)
                        showEditor = false
                    }
                    .navigationTitle(L("Edit pages", "Sunting halaman"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Close", "Tutup")) { showEditor = false } } }
                }
            }
        }
    }

    private func pageCell(_ i: Int) -> some View {
        let on = model.selected.contains(i)
        return VStack(spacing: 6) {
            PageThumb(page: model.doc.page(at: i), version: model.version, size: CGSize(width: 110, height: 146))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Color.fsTeal : .clear, lineWidth: 3))
                .onTapGesture { if on { model.selected.remove(i) } else { model.selected.insert(i) } }
            HStack(spacing: 10) {
                Text("\(i + 1)").font(.caption.weight(.bold))
                Menu {
                    Button { model.rotate(i, by: -90) } label: { Label(L("Rotate left", "Putar kiri"), systemImage: "rotate.left") }
                    Button { model.rotate(i, by: 90) } label: { Label(L("Rotate right", "Putar kanan"), systemImage: "rotate.right") }
                    Button { model.move(i, by: -1) } label: { Label(L("Move earlier", "Alih ke depan"), systemImage: "arrow.left") }
                    Button { model.move(i, by: 1) } label: { Label(L("Move later", "Alih ke belakang"), systemImage: "arrow.right") }
                    Button { model.duplicate(i) } label: { Label(L("Duplicate", "Gandakan"), systemImage: "plus.square.on.square") }
                    Button { model.blank(after: i) } label: { Label(L("Insert blank page after", "Sisip halaman kosong selepas"), systemImage: "doc.badge.plus") }
                    Button(role: .destructive) { model.delete([i]) } label: { Label(L("Delete", "Padam"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title3).foregroundColor(.fsTeal)
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button { for i in model.selected { model.rotate(i, by: 90) } } label: { Label(L("Rotate", "Putar"), systemImage: "rotate.right") }
                .buttonStyle(SoftButtonStyle())
            Button { model.delete(model.selected) } label: { Label(L("Delete", "Padam"), systemImage: "trash") }
                .buttonStyle(SoftButtonStyle(tint: .fsRed))
            Button { extractSelected() } label: { Label(L("Extract", "Ekstrak"), systemImage: "square.and.arrow.up") }
                .buttonStyle(SoftButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private func apply(_ op: @escaping (URL, URL) throws -> Void) {
        busy = true; error = nil
        let model = self.model
        let src: URL
        do { src = try model.tempFile() } catch { self.error = error.localizedDescription; busy = false; return }
        Task.detached(priority: .userInitiated) {
            do {
                let out = Workspace.unique(Workspace.newDir("Work"), "result.pdf")
                try op(src, out)
                let data = try Data(contentsOf: out)
                await MainActor.run { model.replace(with: data); busy = false }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; busy = false }
            }
        }
    }

    private func handlePrompt() {
        let text = promptText
        switch prompt {
        case .watermark:
            apply { u, o in try StampEngine.watermark(u, text: text, style: 0, colorIndex: 0, opacity: 0.18, fontSize: 64, range: "", out: o) }
        case .protect:
            guard text.count >= 4 else { error = L("Use at least 4 characters.", "Gunakan sekurang-kurangnya 4 aksara."); break }
            do {
                let src = try model.tempFile()
                let out = Workspace.unique(Workspace.newDir("Out"), model.name + "_protected.pdf")
                try StampEngine.protect(src, password: text, out: out)
                result = ToolResult(files: [out], message: L("Protected copy saved.", "Salinan dilindungi disimpan."))
            } catch { self.error = error.localizedDescription }
        case .none: break
        }
        prompt = nil
    }

    private func extractSelected() {
        do {
            let src = try model.tempFile()
            let out = Workspace.unique(Workspace.newDir("Out"), model.name + "_extracted.pdf")
            try OrganizeEngine.subset(src, indices: model.selected.sorted(), out: out)
            result = ToolResult(files: [out])
        } catch { self.error = error.localizedDescription }
    }

    private func export() {
        do {
            let out = Workspace.unique(Workspace.newDir("Out"), model.name + "_edited.pdf")
            guard let d = model.doc.dataRepresentation() else { throw IQError.saveFailed }
            try d.write(to: out)
            result = ToolResult(files: [out], message: L("\(model.doc.pageCount) pages saved.", "\(model.doc.pageCount) halaman disimpan."))
        } catch { self.error = error.localizedDescription }
    }
}
