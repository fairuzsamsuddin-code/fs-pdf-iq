import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var router: Router
    @State private var query = ""
    @State private var category: ToolCategory? = nil
    @State private var showImporter = false

    private var filtered: [Tool] {
        Catalog.all.filter { t in
            (category == nil || t.category == category) &&
            (query.isEmpty || t.name.localizedCaseInsensitiveContains(query) || t.desc.localizedCaseInsensitiveContains(query)
             || t.en.localizedCaseInsensitiveContains(query) || t.ms.localizedCaseInsensitiveContains(query))
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if query.isEmpty { hero; workbenchCard }
                categoryChips
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filtered) { tool in
                        Button { router.go(tool) } label: { ToolCard(tool: tool) }
                            .buttonStyle(.plain)
                    }
                }
                if filtered.isEmpty {
                    Text(L("No tools match “\(query)”.", "Tiada alat sepadan dengan “\(query)”."))
                        .foregroundColor(.secondary).padding(.top, 30)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: L("Search 48 tools", "Cari 48 alat"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Wordmark(size: 20) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image, UTTypes.docx, UTTypes.xlsx, UTTypes.pptx, .rtf, .plainText, .html, .commaSeparatedText, UTTypes.md],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first { router.open(u) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("PDF tools", "Alat PDF")).font(.title2.weight(.bold))
                Text(L("Private • works offline • free", "Peribadi • berfungsi luar talian • percuma"))
                    .font(.footnote).foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: $settings.lang) {
                Text("BM").tag(Lang.ms)
                Text("EN").tag(Lang.en)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            Menu {
                Picker(L("Appearance", "Paparan"), selection: $settings.appearance) {
                    Label(L("Light", "Cerah"), systemImage: "sun.max").tag(0)
                    Label(L("Dark", "Gelap"), systemImage: "moon").tag(1)
                    Label(L("Device", "Ikut peranti"), systemImage: "iphone").tag(2)
                }
            } label: {
                Image(systemName: settings.appearance == 1 ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.fsTeal)
                    .frame(width: 36, height: 36)
                    .glass(18)
            }
        }
        .padding(.top, 6)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Friendly PDF tools,\nsimple & private", "Alat PDF mesra,\nmudah & peribadi"))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Merge, split, compress, convert, sign and edit PDFs right on your iPhone or iPad. Files never leave your device.",
                   "Gabung, pisah, mampat, tukar, tandatangan dan sunting PDF terus di iPhone atau iPad. Fail tidak pernah meninggalkan peranti anda."))
                .font(.subheadline).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                chip("lock.shield.fill", L("On-device", "Dalam peranti"), .fsTeal)
                chip("bolt.fill", L("Instant", "Pantas"), .orange)
                chip("person.crop.circle.badge.xmark", L("No sign-up", "Tiada daftar"), .fsRed)
            }
            Button { showImporter = true } label: {
                Label(L("Open a file", "Buka fail"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            Text(L("PDF · Word · Excel · PowerPoint · Markdown · HTML · Photos", "PDF · Word · Excel · PowerPoint · Markdown · HTML · Foto"))
                .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity)
        }
        .padding(18)
        .glass(26)
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var workbenchCard: some View {
        Button { router.go(Catalog.workbench) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.fsRed, .fsTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "hammer.fill").foregroundColor(.white).font(.title3)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Catalog.workbench.name).font(.headline)
                        BadgeView(badge: .new)
                    }
                    Text(Catalog.workbench.desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding(14)
            .glass(22)
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                catChip(nil, L("All", "Semua"), Catalog.all.count)
                ForEach(ToolCategory.allCases) { c in
                    catChip(c, c.title, Catalog.all.filter { $0.category == c }.count)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func catChip(_ c: ToolCategory?, _ title: String, _ count: Int) -> some View {
        let selected = category == c
        return Button {
            withAnimation(.spring(response: 0.3)) { category = c }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(count)").font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((selected ? Color.white : Color.secondary).opacity(0.22), in: Capsule())
            }
            .foregroundColor(selected ? .white : .primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background {
                if selected { Capsule().fill(c?.color ?? .fsRed) } else { Capsule().fill(.ultraThinMaterial) }
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Wordmark(size: 16)
            Text(L("All processing happens on this device. Nothing is uploaded.",
                   "Semua pemprosesan berlaku pada peranti ini. Tiada apa-apa dimuat naik."))
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
}

struct BadgeView: View {
    let badge: Badge
    var body: some View {
        Text(badge == .popular ? L("Popular", "Popular") : L("New", "Baharu"))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(badge == .popular ? Color.fsRed : Color.fsTeal, in: Capsule())
    }
}

struct ToolCard: View {
    let tool: Tool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tool.category.color.opacity(0.14))
                    Image(systemName: tool.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tool.category.color)
                }
                .frame(width: 42, height: 42)
                Spacer()
                if let b = tool.badge { BadgeView(badge: b) }
            }
            Text(tool.name)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(tool.desc)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .glass(20)
        .contentShape(Rectangle())
    }
}
