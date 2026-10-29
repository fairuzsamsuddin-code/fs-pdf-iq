import SwiftUI
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// MARK: - Result model

struct ToolResult {
    var files: [URL]
    var message: String? = nil
    var preview: String? = nil
}

// MARK: - Header

struct ToolHeader: View {
    let tool: Tool
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tool.category.color.opacity(0.15))
                Image(systemName: tool.icon).font(.system(size: 22, weight: .semibold)).foregroundColor(tool.category.color)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name).font(.title3.weight(.bold))
                Text(tool.desc).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glass(22)
    }
}

// MARK: - File input

struct FileInputSection: View {
    let kind: InputKind
    @Binding var files: [URL]
    var allowPhotos: Bool { kind == .images || kind == .imagesOrPDF }
    var multiple: Bool { kind == .pdfs || kind == .images || kind == .imagesOrPDF || kind == .twoPDFs }
    var maxFiles: Int { kind == .twoPDFs ? 2 : (multiple ? 200 : 1) }

    @State private var showImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loadingPhotos = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: kind == .twoPDFs ? L("Files to compare (A, then B)", "Fail untuk dibanding (A, kemudian B)") : L("Your files", "Fail anda"))
            if files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 34)).foregroundColor(.fsTeal)
                    Text(emptyHint).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundColor(.fsTeal.opacity(0.5)))
            } else {
                ForEach(Array(files.enumerated()), id: \.element) { i, f in
                    FileRow(url: f, index: kind == .twoPDFs ? (i == 0 ? "A" : "B") : (files.count > 1 ? "\(i + 1)" : nil),
                            canMoveUp: multiple && i > 0, canMoveDown: multiple && i < files.count - 1,
                            onUp: { files.swapAt(i, i - 1) }, onDown: { files.swapAt(i, i + 1) },
                            onDelete: { files.remove(at: i) })
                }
            }
            if files.count < maxFiles {
                HStack(spacing: 10) {
                    Button { showImporter = true } label: {
                        Label(files.isEmpty ? L("Choose file", "Pilih fail") : L("Add more", "Tambah lagi"), systemImage: "folder")
                    }
                    .buttonStyle(SoftButtonStyle())
                    if allowPhotos {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 100, matching: .images) {
                            Label(L("Photos", "Foto"), systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(SoftButtonStyle(tint: .fsRed))
                    }
                    if loadingPhotos { ProgressView() }
                }
            }
        }
        .padding(16)
        .glass(22)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: UTTypes.types(for: kind), allowsMultipleSelection: multiple) { result in
            if case .success(let urls) = result {
                let copies = Workspace.importCopies(urls)
                files.append(contentsOf: copies.prefix(maxFiles - files.count))
            }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            loadingPhotos = true
            Task {
                var urls: [URL] = []
                for (i, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let u = Workspace.saveData(data, name: String(format: "photo_%03d.jpg", i + 1)) {
                        urls.append(u)
                    }
                }
                await MainActor.run {
                    files.append(contentsOf: urls)
                    photoItems = []
                    loadingPhotos = false
                }
            }
        }
    }

    private var emptyHint: String {
        switch kind {
        case .images: return L("Add photos or image files", "Tambah foto atau fail imej")
        case .imagesOrPDF: return L("Add a PDF, photos or images", "Tambah PDF, foto atau imej")
        case .pdfs: return L("Add two or more PDFs", "Tambah dua atau lebih PDF")
        case .twoPDFs: return L("Add the original and the new version", "Tambah versi asal dan versi baharu")
        case .word: return L("Add a Word (.docx), RTF or TXT file", "Tambah fail Word (.docx), RTF atau TXT")
        case .excel: return L("Add an Excel (.xlsx) or CSV file", "Tambah fail Excel (.xlsx) atau CSV")
        case .powerpoint: return L("Add a PowerPoint (.pptx) file", "Tambah fail PowerPoint (.pptx)")
        case .html: return L("Add an .html file — or paste code below", "Tambah fail .html — atau tampal kod di bawah")
        case .markdown: return L("Add a .md file — or paste text below", "Tambah fail .md — atau tampal teks di bawah")
        default: return L("Add a PDF file", "Tambah fail PDF")
        }
    }
}

struct FileRow: View {
    let url: URL
    var index: String? = nil
    var canMoveUp = false, canMoveDown = false
    var onUp: () -> Void = {}, onDown: () -> Void = {}, onDelete: () -> Void = {}
    @State private var thumb: UIImage? = nil
    @State private var pages = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let t = thumb {
                    Image(uiImage: t).resizable().scaledToFit()
                } else {
                    Image(systemName: fileIcon(url)).font(.title2).foregroundColor(.fsTeal)
                }
            }
            .frame(width: 42, height: 52)
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let i = index { Text(i).font(.caption2.weight(.bold)).foregroundColor(.white).padding(4).background(Color.fsTeal, in: Circle()) }
                    Text(url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                }
                Text(pages > 0 ? "\(Workspace.sizeString(url)) · " + L("\(pages) pages", "\(pages) halaman") : Workspace.sizeString(url))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if canMoveUp { Button(action: onUp) { Image(systemName: "chevron.up") }.buttonStyle(.borderless) }
            if canMoveDown { Button(action: onDown) { Image(systemName: "chevron.down") }.buttonStyle(.borderless) }
            Button(role: .destructive, action: onDelete) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                .buttonStyle(.borderless)
        }
        .task(id: url) {
            let u = url
            let result: (UIImage?, Int) = await Task.detached { () -> (UIImage?, Int) in
                if u.pathExtension.lowercased() == "pdf", let d = PDFDocument(url: u) {
                    return (d.page(at: 0)?.thumbnail(of: CGSize(width: 84, height: 104), for: .cropBox), d.pageCount)
                }
                if let img = UIImage(contentsOfFile: u.path) {
                    return (img.preparingThumbnail(of: CGSize(width: 84, height: 104)) ?? img, 0)
                }
                return (nil, 0)
            }.value
            thumb = result.0
            pages = result.1
        }
    }
}

func fileIcon(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "pdf": return "doc.fill"
    case "jpg", "jpeg", "png", "heic", "webp", "jp2": return "photo"
    case "docx", "doc": return "doc.richtext"
    case "xlsx", "csv": return "tablecells"
    case "pptx": return "play.rectangle"
    case "zip": return "doc.zipper"
    case "txt", "md": return "text.alignleft"
    case "dxf": return "pencil.and.ruler"
    default: return "doc"
    }
}

// MARK: - Results

struct ResultsSection: View {
    let result: ToolResult
    @State private var preview: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.fsTeal).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Done!", "Siap!")).font(.headline)
                    if let m = result.message { Text(m).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer()
            }
            ForEach(result.files, id: \.self) { f in
                HStack(spacing: 12) {
                    Image(systemName: fileIcon(f)).font(.title3).foregroundColor(.fsRed).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Text(Workspace.sizeString(f)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { preview = f } label: { Image(systemName: "eye") }.buttonStyle(.borderless)
                    ShareLink(item: f) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            if result.files.count > 1 {
                ShareLink(items: result.files) {
                    Label(L("Share / save all \(result.files.count) files", "Kongsi / simpan semua \(result.files.count) fail"), systemImage: "square.and.arrow.up.on.square")
                }
                .buttonStyle(PrimaryButtonStyle(color: .fsTeal))
            } else if let f = result.files.first {
                ShareLink(item: f) {
                    Label(L("Save or share", "Simpan atau kongsi"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle(color: .fsTeal))
            }
            if let p = result.preview, !p.isEmpty {
                ScrollView {
                    Text(p.count > 6000 ? String(p.prefix(6000)) + "…" : p)
                        .font(.footnote.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 260)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .glass(22)
        .quickLookPreview($preview)
    }
}

// MARK: - PDFKit wrappers

struct PDFKitView: UIViewRepresentable {
    let pdfView: PDFView
    func makeUIView(context: Context) -> PDFView { pdfView }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

func makePDFView(_ doc: PDFDocument?) -> PDFView {
    let v = PDFView()
    v.autoScales = true
    v.displayMode = .singlePageContinuous
    v.displayDirection = .vertical
    v.backgroundColor = UIColor.secondarySystemBackground
    v.document = doc
    return v
}

struct PageThumb: View {
    let page: PDFPage?
    var version: Int = 0
    var size = CGSize(width: 110, height: 150)
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Color.white
            if let i = image { Image(uiImage: i).resizable().scaledToFit() } else { ProgressView() }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        .task(id: version) {
            image = page?.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .cropBox)
        }
    }
}

// MARK: - Small option controls

struct OptionRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundColor(.secondary)
            content
        }
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldStyle()) }
}

struct RunButton: View {
    let title: String
    let busy: Bool
    let progress: Double
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? L("Working…", "Sedang diproses…") : title)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!enabled || busy)
            .opacity(enabled ? 1 : 0.5)
            if busy && progress > 0 && progress < 1 {
                ProgressView(value: progress).tint(.fsTeal)
            }
        }
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.fsRed)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.fsRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}
