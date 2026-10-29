import SwiftUI
import UniformTypeIdentifiers

enum ToolCategory: String, CaseIterable, Identifiable {
    case organize, optimize, convert, edit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .organize: return L("Organize", "Susun")
        case .optimize: return L("Optimize", "Optimum")
        case .convert: return L("Convert", "Tukar")
        case .edit: return L("Edit & Secure", "Sunting & Lindung")
        }
    }
    var color: Color {
        switch self {
        case .organize: return .fsTeal
        case .optimize: return Color(red: 0.93, green: 0.52, blue: 0.08)
        case .convert: return Color(red: 0.2, green: 0.42, blue: 0.86)
        case .edit: return .fsRed
        }
    }
}

enum InputKind {
    case pdf, pdfs, twoPDFs, images, imagesOrPDF, word, excel, powerpoint, html, markdown, none
}

enum Badge { case popular, new }

struct Tool: Identifiable, Hashable {
    let id: String
    let icon: String
    let category: ToolCategory
    let en: String, ms: String
    let enDesc: String, msDesc: String
    var badge: Badge? = nil
    let input: InputKind

    var name: String { L(en, ms) }
    var desc: String { L(enDesc, msDesc) }

    static func == (a: Tool, b: Tool) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum UTTypes {
    static let docx = UTType(filenameExtension: "docx") ?? .data
    static let doc = UTType(filenameExtension: "doc") ?? .data
    static let xlsx = UTType(filenameExtension: "xlsx") ?? .data
    static let xls = UTType(filenameExtension: "xls") ?? .data
    static let pptx = UTType(filenameExtension: "pptx") ?? .data
    static let ppt = UTType(filenameExtension: "ppt") ?? .data
    static let md = UTType(filenameExtension: "md") ?? .plainText

    static func types(for k: InputKind) -> [UTType] {
        switch k {
        case .pdf, .pdfs, .twoPDFs: return [.pdf]
        case .images: return [.image]
        case .imagesOrPDF: return [.image, .pdf]
        case .word: return [docx, doc, .rtf, .plainText]
        case .excel: return [xlsx, xls, .commaSeparatedText]
        case .powerpoint: return [pptx, ppt]
        case .html: return [.html, .plainText]
        case .markdown: return [md, .plainText]
        case .none: return []
        }
    }
}

enum Catalog {
    static let workbench = Tool(id: "workbench", icon: "hammer.fill", category: .organize, en: "PDF Workbench", ms: "Meja Kerja PDF",
                                enDesc: "Open a PDF once and organise, edit, number, compress and protect it in one place, with undo.",
                                msDesc: "Buka PDF sekali dan susun, sunting, nomborkan, mampatkan serta lindungi di satu tempat, dengan buat asal.",
                                badge: .new, input: .pdf)

    static let all: [Tool] = [
        // Organize
        Tool(id: "merge-pdf", icon: "doc.on.doc.fill", category: .organize, en: "Merge PDF", ms: "Gabung PDF",
             enDesc: "Combine multiple PDFs into a single file in the exact order you want.",
             msDesc: "Gabungkan beberapa PDF menjadi satu fail mengikut susunan yang anda mahu.", badge: .popular, input: .pdfs),
        Tool(id: "split-pdf", icon: "scissors", category: .organize, en: "Split PDF", ms: "Pisah PDF",
             enDesc: "Separate every page or extract custom page ranges into individual files.",
             msDesc: "Asingkan setiap halaman atau julat halaman tertentu kepada fail berasingan.", input: .pdf),
        Tool(id: "remove-pages", icon: "trash", category: .organize, en: "Remove Pages", ms: "Buang Halaman",
             enDesc: "Delete unwanted pages from your document with quick visual selection.",
             msDesc: "Padam halaman yang tidak diperlukan dengan pilihan visual yang pantas.", input: .pdf),
        Tool(id: "extract-pages", icon: "square.and.arrow.up.on.square", category: .organize, en: "Extract Pages", ms: "Ekstrak Halaman",
             enDesc: "Pick specific pages and bundle them into a clean, new PDF file.",
             msDesc: "Pilih halaman tertentu dan himpunkan ke dalam fail PDF baharu.", input: .pdf),
        Tool(id: "reorder-pages", icon: "arrow.up.arrow.down", category: .organize, en: "Reorder Pages", ms: "Susun Semula Halaman",
             enDesc: "Rearrange and sort PDF pages into your preferred reading sequence.",
             msDesc: "Susun semula halaman PDF mengikut urutan bacaan pilihan anda.", input: .pdf),
        Tool(id: "organize-pdf", icon: "square.grid.2x2.fill", category: .organize, en: "Organize PDF", ms: "Urus PDF",
             enDesc: "Rearrange, rotate, delete, duplicate and add blank pages visually.",
             msDesc: "Susun, putar, padam, gandakan dan tambah halaman kosong secara visual.", badge: .new, input: .pdf),
        Tool(id: "rotate-pdf", icon: "rotate.right", category: .organize, en: "Rotate PDF", ms: "Putar PDF",
             enDesc: "Rotate all or selected pages by 90°, 180° or 270°.",
             msDesc: "Putar semua atau halaman terpilih sebanyak 90°, 180° atau 270°.", input: .pdf),
        Tool(id: "booklet-pdf", icon: "book.fill", category: .organize, en: "Booklet Creator", ms: "Pembuat Buku Kecil",
             enDesc: "Impose pages into a foldable saddle-stitch booklet for printing.",
             msDesc: "Susun halaman menjadi buku kecil berlipat untuk dicetak.", badge: .new, input: .pdf),
        Tool(id: "n-up-pdf", icon: "rectangle.split.2x2", category: .organize, en: "Multiple Pages per Sheet", ms: "Berbilang Halaman Sehelai",
             enDesc: "Place 2, 4, 6, 9 or 16 pages on one A4 sheet to save paper.",
             msDesc: "Letak 2, 4, 6, 9 atau 16 halaman pada sehelai A4 untuk jimat kertas.", badge: .new, input: .pdf),

        // Optimize
        Tool(id: "compress-pdf", icon: "arrow.down.right.and.arrow.up.left", category: .optimize, en: "Compress PDF", ms: "Mampatkan PDF",
             enDesc: "Reduce file size — e.g. under 200 KB for portals. Pages are re-saved as images.",
             msDesc: "Kecilkan saiz fail — cth. bawah 200 KB untuk portal. Halaman disimpan semula sebagai imej.", badge: .popular, input: .pdf),
        Tool(id: "crop-pdf", icon: "crop", category: .optimize, en: "Crop PDF", ms: "Pangkas PDF",
             enDesc: "Trim the outer margins of every page.",
             msDesc: "Potong margin luar setiap halaman.", input: .pdf),
        Tool(id: "pdf-to-grayscale", icon: "circle.lefthalf.filled", category: .optimize, en: "PDF to Grayscale", ms: "PDF ke Skala Kelabu",
             enDesc: "Convert a colour PDF to black & white to save printer ink.",
             msDesc: "Tukar PDF berwarna kepada hitam putih untuk jimat dakwat.", input: .pdf),
        Tool(id: "repair-pdf", icon: "wrench.and.screwdriver.fill", category: .optimize, en: "Repair PDF", ms: "Baiki PDF",
             enDesc: "Rebuild damaged PDFs and recover what can be saved.",
             msDesc: "Bina semula PDF rosak dan pulihkan apa yang boleh diselamatkan.", input: .pdf),
        Tool(id: "flatten-pdf", icon: "square.stack.3d.down.right.fill", category: .optimize, en: "Flatten PDF", ms: "Ratakan PDF",
             enDesc: "Lock form fields and annotations into permanent page content.",
             msDesc: "Kunci medan borang dan anotasi menjadi kandungan halaman kekal.", badge: .new, input: .pdf),
        Tool(id: "pdf-to-pdfa", icon: "archivebox.fill", category: .optimize, en: "Convert to PDF/A", ms: "Tukar ke PDF/A",
             enDesc: "Archive-format PDF/A-2b for e-Filing, LHDN and long-term storage.",
             msDesc: "PDF/A-2b format arkib untuk e-Filing, LHDN dan simpanan jangka panjang.", badge: .new, input: .pdf),
        Tool(id: "magic-filter", icon: "wand.and.stars", category: .optimize, en: "Magic Scan Filter", ms: "Penapis Imbasan Ajaib",
             enDesc: "Whiten paper, remove shadows and sharpen phone-camera scans.",
             msDesc: "Putihkan kertas, buang bayang dan tajamkan imbasan kamera telefon.", badge: .new, input: .imagesOrPDF),
        Tool(id: "slide-ink-saver", icon: "drop.fill", category: .optimize, en: "Slide Ink Saver", ms: "Penjimat Dakwat Slaid",
             enDesc: "Turn dark lecture slides into white backgrounds with dark text.",
             msDesc: "Tukar slaid kuliah gelap kepada latar putih dengan teks gelap.", badge: .popular, input: .pdf),
        Tool(id: "thesis-margin", icon: "ruler.fill", category: .optimize, en: "Thesis & FYP Margins", ms: "Margin Tesis & FYP",
             enDesc: "Fit pages inside binding margins (e.g. 3.8 cm left gutter).",
             msDesc: "Muatkan halaman dalam margin jilid (cth. margin kiri 3.8 cm).", badge: .new, input: .pdf),
        Tool(id: "cornell-notes", icon: "note.text", category: .optimize, en: "Cornell Notes", ms: "Nota Cornell",
             enDesc: "Turn lecture slides into Cornell note-taking handouts.",
             msDesc: "Jadikan slaid kuliah sebagai edaran nota gaya Cornell.", badge: .new, input: .pdf),
        Tool(id: "ocr-pdf", icon: "text.viewfinder", category: .optimize, en: "OCR PDF", ms: "OCR PDF",
             enDesc: "Recognise text in scans and photos and make them searchable.",
             msDesc: "Kenal pasti teks dalam imbasan dan foto serta jadikannya boleh dicari.", badge: .new, input: .imagesOrPDF),

        // Convert
        Tool(id: "jpg-to-pdf", icon: "photo.on.rectangle", category: .convert, en: "JPG to PDF", ms: "JPG ke PDF",
             enDesc: "Convert photos (JPG, PNG, HEIC) into one PDF.",
             msDesc: "Tukar foto (JPG, PNG, HEIC) menjadi satu PDF.", input: .images),
        Tool(id: "pdf-to-jpg", icon: "photo.fill", category: .convert, en: "PDF to JPG", ms: "PDF ke JPG",
             enDesc: "Save every page as a sharp JPG image.",
             msDesc: "Simpan setiap halaman sebagai imej JPG yang tajam.", input: .pdf),
        Tool(id: "pdf-to-png", icon: "photo.stack", category: .convert, en: "PDF to PNG", ms: "PDF ke PNG",
             enDesc: "Lossless PNG pages, optionally with transparent background.",
             msDesc: "Halaman PNG tanpa kehilangan kualiti, boleh berlatar lutsinar.", input: .pdf),
        Tool(id: "pdf-to-text", icon: "text.alignleft", category: .convert, en: "PDF to Text", ms: "PDF ke Teks",
             enDesc: "Extract selectable text into a TXT file.",
             msDesc: "Ekstrak teks boleh pilih ke fail TXT.", input: .pdf),
        Tool(id: "pdf-to-word", icon: "doc.richtext.fill", category: .convert, en: "PDF to Word", ms: "PDF ke Word",
             enDesc: "Editable .docx with paragraphs, or an exact-layout copy.",
             msDesc: ".docx boleh sunting dengan perenggan, atau salinan susun atur tepat.", badge: .new, input: .pdf),
        Tool(id: "word-to-pdf", icon: "doc.text.fill", category: .convert, en: "Word to PDF", ms: "Word ke PDF",
             enDesc: "Turn .docx, RTF or TXT documents into A4 PDF.",
             msDesc: "Tukar dokumen .docx, RTF atau TXT kepada PDF A4.", badge: .new, input: .word),
        Tool(id: "pdf-to-excel", icon: "tablecells.fill", category: .convert, en: "PDF to Excel", ms: "PDF ke Excel",
             enDesc: "Pull tables (e.g. bank statements) into Excel and CSV.",
             msDesc: "Tarik jadual (cth. penyata bank) ke Excel dan CSV.", badge: .popular, input: .pdf),
        Tool(id: "excel-to-pdf", icon: "tablecells.badge.ellipsis", category: .convert, en: "Excel to PDF", ms: "Excel ke PDF",
             enDesc: "Print .xlsx and CSV sheets as tidy PDF tables.",
             msDesc: "Cetak helaian .xlsx dan CSV sebagai jadual PDF yang kemas.", badge: .new, input: .excel),
        Tool(id: "pdf-to-pptx", icon: "play.rectangle.fill", category: .convert, en: "PDF to PowerPoint", ms: "PDF ke PowerPoint",
             enDesc: "Every page becomes a slide in a .pptx deck.",
             msDesc: "Setiap halaman menjadi slaid dalam fail .pptx.", badge: .new, input: .pdf),
        Tool(id: "pptx-to-pdf", icon: "rectangle.on.rectangle", category: .convert, en: "PowerPoint to PDF", ms: "PowerPoint ke PDF",
             enDesc: "Slides with backgrounds, shapes, pictures, tables and text.",
             msDesc: "Slaid dengan latar, bentuk, gambar, jadual dan teks.", badge: .new, input: .powerpoint),
        Tool(id: "html-to-pdf", icon: "chevron.left.forwardslash.chevron.right", category: .convert, en: "HTML to PDF", ms: "HTML ke PDF",
             enDesc: "Convert HTML code or .html files into PDF.",
             msDesc: "Tukar kod HTML atau fail .html kepada PDF.", input: .html),
        Tool(id: "markdown-to-pdf", icon: "number", category: .convert, en: "Markdown to PDF", ms: "Markdown ke PDF",
             enDesc: "Headings, lists, code and tables from .md notes.",
             msDesc: "Tajuk, senarai, kod dan jadual daripada nota .md.", badge: .new, input: .markdown),
        Tool(id: "pdf-to-dwg", icon: "pencil.and.ruler.fill", category: .convert, en: "PDF to CAD (DXF)", ms: "PDF ke CAD (DXF)",
             enDesc: "Vector lines and text from drawings as DXF for AutoCAD.",
             msDesc: "Garisan vektor dan teks lukisan sebagai DXF untuk AutoCAD.", badge: .new, input: .pdf),
        Tool(id: "extract-images", icon: "photo.on.rectangle.angled", category: .convert, en: "Extract Images", ms: "Ekstrak Imej",
             enDesc: "Save the photos and graphics inside a PDF at original quality.",
             msDesc: "Simpan foto dan grafik dalam PDF pada kualiti asal.", badge: .new, input: .pdf),
        Tool(id: "scan-to-pdf", icon: "doc.viewfinder.fill", category: .convert, en: "Scan to PDF", ms: "Imbas ke PDF",
             enDesc: "Scan paper with the camera into a clean PDF.",
             msDesc: "Imbas kertas dengan kamera menjadi PDF yang bersih.", input: .none),
        Tool(id: "pdf-to-ai", icon: "sparkles", category: .convert, en: "Summarize with AI", ms: "Ringkas dengan AI",
             enDesc: "Send the text to ChatGPT, Claude or Gemini with ready-made prompts.",
             msDesc: "Hantar teks ke ChatGPT, Claude atau Gemini dengan arahan sedia ada.", badge: .new, input: .pdf),
        Tool(id: "listen-pdf", icon: "speaker.wave.2.fill", category: .convert, en: "Listen to PDF", ms: "Dengar PDF",
             enDesc: "Read documents aloud in Bahasa Melayu or English.",
             msDesc: "Bacakan dokumen dalam Bahasa Melayu atau Inggeris.", badge: .new, input: .pdf),

        // Edit & secure
        Tool(id: "preview-pdf", icon: "eye.fill", category: .edit, en: "Preview PDF", ms: "Pratonton PDF",
             enDesc: "Read with zoom, search, thumbnails and print.",
             msDesc: "Baca dengan zum, carian, lakaran kecil dan cetak.", badge: .popular, input: .pdf),
        Tool(id: "edit-pdf", icon: "pencil.tip.crop.circle.fill", category: .edit, en: "Edit PDF", ms: "Sunting PDF",
             enDesc: "Add text, whiteout, highlight, draw, ticks, signatures and images.",
             msDesc: "Tambah teks, padam putih, serlah, lukis, tanda, tandatangan dan imej.", badge: .new, input: .pdf),
        Tool(id: "sign-pdf", icon: "signature", category: .edit, en: "Sign PDF", ms: "Tandatangan PDF",
             enDesc: "Draw or type your signature and place it on any page.",
             msDesc: "Lukis atau taip tandatangan anda dan letakkan di mana-mana halaman.", badge: .popular, input: .pdf),
        Tool(id: "watermark", icon: "seal.fill", category: .edit, en: "Add Watermark", ms: "Tambah Tera Air",
             enDesc: "Stamp CONFIDENTIAL, DRAFT or your own text across pages.",
             msDesc: "Cop SULIT, DRAF atau teks sendiri merentasi halaman.", input: .pdf),
        Tool(id: "page-numbers", icon: "number.circle.fill", category: .edit, en: "Page Numbers", ms: "Nombor Halaman",
             enDesc: "Add neat page numbers to the header or footer.",
             msDesc: "Tambah nombor halaman yang kemas di pengepala atau pengaki.", input: .pdf),
        Tool(id: "bates-numbering", icon: "barcode", category: .edit, en: "Bates Numbering", ms: "Penomboran Bates",
             enDesc: "Sequential legal numbers with prefix for court filing.",
             msDesc: "Nombor undang-undang berturutan dengan awalan untuk failan mahkamah.", badge: .new, input: .pdf),
        Tool(id: "protect-pdf", icon: "lock.fill", category: .edit, en: "Protect PDF", ms: "Lindungi PDF",
             enDesc: "Encrypt your PDF with a password.",
             msDesc: "Sulitkan PDF anda dengan kata laluan.", input: .pdf),
        Tool(id: "unlock-pdf", icon: "lock.open.fill", category: .edit, en: "Unlock PDF", ms: "Buka Kunci PDF",
             enDesc: "Remove the password and restrictions (you need the password).",
             msDesc: "Buang kata laluan dan sekatan (anda perlu tahu kata laluannya).", input: .pdf),
        Tool(id: "redact-pdf", icon: "rectangle.fill", category: .edit, en: "Redact PDF", ms: "Redaksi PDF",
             enDesc: "Permanently black out sensitive text such as IC numbers.",
             msDesc: "Hitamkan teks sensitif secara kekal seperti nombor IC.", input: .pdf),
        Tool(id: "edit-metadata", icon: "info.circle.fill", category: .edit, en: "Edit Metadata", ms: "Sunting Metadata",
             enDesc: "Change title, author, subject and keywords.",
             msDesc: "Tukar tajuk, pengarang, subjek dan kata kunci.", input: .pdf),
        Tool(id: "compare-pdf", icon: "rectangle.split.2x1.fill", category: .edit, en: "Compare PDF", ms: "Banding PDF",
             enDesc: "Spot changes between two versions, highlighted in red.",
             msDesc: "Kesan perubahan antara dua versi, ditanda merah.", badge: .new, input: .twoPDFs)
    ]

    static func tool(_ id: String) -> Tool? {
        id == workbench.id ? workbench : all.first { $0.id == id }
    }

    /// Picks the right tool for a file someone opened or shared into the app.
    static func toolFor(fileURL: URL) -> Tool {
        switch fileURL.pathExtension.lowercased() {
        case "pdf": return workbench
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp": return tool("jpg-to-pdf")!
        case "docx", "doc", "rtf", "txt": return tool("word-to-pdf")!
        case "xlsx", "xls", "csv": return tool("excel-to-pdf")!
        case "pptx", "ppt": return tool("pptx-to-pdf")!
        case "html", "htm": return tool("html-to-pdf")!
        case "md", "markdown": return tool("markdown-to-pdf")!
        default: return workbench
        }
    }
}
