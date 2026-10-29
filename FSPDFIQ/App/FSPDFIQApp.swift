import SwiftUI

@main
struct FSPDFIQApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = Router()

    init() {
        Workspace.clearOld()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lang"), i + 1 < args.count, let l = Lang(rawValue: args[i + 1]) { AppSettings.shared.lang = l }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(settings.lang)
                .environmentObject(settings)
                .environmentObject(router)
                .preferredColorScheme(settings.scheme)
                .tint(.fsRed)
                .onOpenURL { router.open($0) }
        }
    }
}

final class Router: ObservableObject {
    @Published var path = NavigationPath()
    private var pending: [String: [URL]] = [:]

    func open(_ url: URL) {
        let copies = Workspace.importCopies([url])
        guard let first = copies.first else { return }
        let tool = Catalog.toolFor(fileURL: first)
        go(tool, files: copies)
    }

    func go(_ tool: Tool, files: [URL] = []) {
        if !files.isEmpty { pending[tool.id] = files }
        path.append(tool)
    }

    func takeFiles(for tool: Tool) -> [URL] {
        defer { pending[tool.id] = nil }
        return pending[tool.id] ?? []
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Tool.self) { tool in
                    ToolHostView(tool: tool, initialFiles: router.takeFiles(for: tool))
                }
        }
        .task {
            let args = ProcessInfo.processInfo.arguments
            if SelfTest.isRequested { await SelfTest.run() }
            if let i = args.firstIndex(of: "-tool"), i + 1 < args.count, let t = Catalog.tool(args[i + 1]) {
                var files: [URL] = []
                if args.contains("-sample") { files = [SelfTest.samplePDF()] }
                router.go(t, files: files)
            }
        }
    }
}
