import UIKit
import WebKit

/// Renders HTML (or a file WebKit can display) into a paginated A4 PDF.
@MainActor
final class WebPDF: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    static func render(html: String, baseURL: URL? = nil, landscape: Bool = false, margin: CGFloat = 36) async throws -> Data {
        let r = WebPDF()
        try await r.load { $0.loadHTMLString(html, baseURL: baseURL) }
        return try r.paginate(landscape: landscape, margin: margin)
    }

    static func render(fileURL: URL, landscape: Bool = false, margin: CGFloat = 28) async throws -> Data {
        let r = WebPDF()
        try await r.load { $0.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent()) }
        return try r.paginate(landscape: landscape, margin: margin)
    }

    private func load(_ start: (WKWebView) -> Void) async throws {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        // Attach off-screen so WebKit lays the page out fully.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first }).first {
            wv.frame.origin = CGPoint(x: -5000, y: 0)
            window.addSubview(wv)
        }
        webView = wv
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            start(wv)
        }
        // give images and fonts a moment to settle
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    private func paginate(landscape: Bool, margin: CGFloat) throws -> Data {
        guard let wv = webView else { throw IQError.saveFailed }
        defer { wv.removeFromSuperview(); webView = nil }
        let paper = landscape ? CGRect(x: 0, y: 0, width: 841.89, height: 595.28) : CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let printable = paper.insetBy(dx: margin, dy: margin)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(wv.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let pages = renderer.numberOfPages
        for i in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        guard pages > 0 else {
            throw IQError.msg("Nothing could be rendered from this file.", "Tiada apa-apa dapat dipaparkan daripada fail ini.")
        }
        return data as Data
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    private func finish(_ error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let e = error { c.resume(throwing: e) } else { c.resume() }
    }

    /// Plain / rich text via the native text print formatter (no WebKit).
    static func renderText(_ attributed: NSAttributedString, margin: CGFloat = 54) -> Data {
        let paper = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UISimpleTextPrintFormatter(attributedText: attributed), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: margin, dy: margin)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
}
