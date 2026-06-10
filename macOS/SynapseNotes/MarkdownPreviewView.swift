import SwiftUI
import AppKit
import WebKit

// MARK: - Markdown Preview with WKWebView

struct MarkdownPreviewView: NSViewRepresentable {
    let markdownContent: String
    let isDarkMode: Bool
    let bodyFontFamily: String
    let monoFontFamily: String
    let fontSize: Int
    let lineHeight: Double
    var currentFileURL: URL? = nil
    var onResolveWikilink: ((String) -> Void)? = nil
    var onToggleCheckbox: ((Int) -> Void)? = nil

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownPreviewView
        var lastMarkdown: String?
        var lastIsDarkMode: Bool?
        var lastBodyFontFamily: String?
        var lastMonoFontFamily: String?
        var lastFontSize: Int?
        var lastLineHeight: Double?
        var lastFileURL: URL?
        var pendingScrollY: CGFloat = 0

        init(_ parent: MarkdownPreviewView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard pendingScrollY > 0 else { return }
            let y = pendingScrollY
            pendingScrollY = 0
            webView.evaluateJavaScript("window.scrollTo(0, \(y))") { _, _ in }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if url.scheme == "wikilink" {
                let destination = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
                parent.onResolveWikilink?(destination)
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // Allow file:// and about: (initial HTML load)
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "toggleCheckbox", let offset = message.body as? Int {
                parent.onToggleCheckbox?(offset)
            }
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController.add(context.coordinator, name: "toggleCheckbox")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard markdownContent != context.coordinator.lastMarkdown ||
              isDarkMode != context.coordinator.lastIsDarkMode ||
              bodyFontFamily != context.coordinator.lastBodyFontFamily ||
              monoFontFamily != context.coordinator.lastMonoFontFamily ||
              fontSize != context.coordinator.lastFontSize ||
              lineHeight != context.coordinator.lastLineHeight ||
              currentFileURL != context.coordinator.lastFileURL else { return }
        context.coordinator.parent = self
        context.coordinator.lastMarkdown = markdownContent
        context.coordinator.lastIsDarkMode = isDarkMode
        context.coordinator.lastBodyFontFamily = bodyFontFamily
        context.coordinator.lastMonoFontFamily = monoFontFamily
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastLineHeight = lineHeight
        context.coordinator.lastFileURL = currentFileURL
        let baseDir = currentFileURL?.deletingLastPathComponent()
        let html = generateHTML(from: markdownContent, isDarkMode: isDarkMode, baseDir: baseDir)
        // Save scroll position before reload, restore after load finishes
        webView.evaluateJavaScript("window.scrollY") { scrollY, _ in
            if let y = scrollY as? CGFloat, y > 0 {
                context.coordinator.pendingScrollY = y
            }
        }
        webView.loadHTMLString(html, baseURL: baseDir)
    }

    private func generateHTML(from markdown: String, isDarkMode: Bool, baseDir: URL? = nil) -> String {
        var html = MarkdownPreviewRenderer().renderBody(from: markdown)
        // Inline local images as data URIs so they render without file:// access
        if let baseDir {
            let imgRegex = try? NSRegularExpression(pattern: #"<img\s+src="([^"]+)""#)
            let nsHTML = html as NSString
            var replacements: [(NSRange, String)] = []
            imgRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: nsHTML.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let srcRange = match.range(at: 1)
                let src = nsHTML.substring(with: srcRange)
                // Skip already-inlined or remote URLs
                guard !src.hasPrefix("data:"), !src.hasPrefix("http://"), !src.hasPrefix("https://") else { return }
                let imageURL = baseDir.appendingPathComponent(src)
                guard let data = try? Data(contentsOf: imageURL) else { return }
                let ext = imageURL.pathExtension.lowercased()
                let mime: String
                switch ext {
                case "png": mime = "image/png"
                case "jpg", "jpeg": mime = "image/jpeg"
                case "gif": mime = "image/gif"
                case "svg": mime = "image/svg+xml"
                case "webp": mime = "image/webp"
                default: mime = "application/octet-stream"
                }
                let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
                replacements.append((srcRange, dataURI))
            }
            // Apply replacements in reverse order to preserve ranges
            for (range, replacement) in replacements.reversed() {
                html = (html as NSString).replacingCharacters(in: range, with: replacement)
            }
        }

        let textColor = isDarkMode ? "#E0E0E0" : "#333333"
        let backgroundColor = isDarkMode ? "#1E1E1E" : "#FFFFFF"
        let borderColor = isDarkMode ? "#444444" : "#CCCCCC"
        let headerBgColor = isDarkMode ? "#2D2D2D" : "#F5F5F5"
        let bodyFontStack = MarkdownPreviewCSS.bodyFontStack(for: bodyFontFamily)
        let monoFontStack = MarkdownPreviewCSS.monoFontStack(for: monoFontFamily)
        let bodyFontSize = MarkdownPreviewCSS.bodyFontSize(for: fontSize)
        let tableFontSize = MarkdownPreviewCSS.tableFontSize(for: fontSize)
        let codeFontSize = MarkdownPreviewCSS.codeFontSize(for: fontSize)
        let bodyLineHeight = MarkdownPreviewCSS.lineHeight(for: lineHeight)
        let h1Size = MarkdownPreviewCSS.headingFontSize(level: 1, baseSize: fontSize)
        let h2Size = MarkdownPreviewCSS.headingFontSize(level: 2, baseSize: fontSize)
        let h3Size = MarkdownPreviewCSS.headingFontSize(level: 3, baseSize: fontSize)
        let h4Size = MarkdownPreviewCSS.headingFontSize(level: 4, baseSize: fontSize)
        let h5Size = MarkdownPreviewCSS.headingFontSize(level: 5, baseSize: fontSize)
        let h6Size = MarkdownPreviewCSS.headingFontSize(level: 6, baseSize: fontSize)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: \(bodyFontStack);
                    font-size: \(bodyFontSize)px;
                    line-height: \(bodyLineHeight);
                    color: \(textColor);
                    background-color: \(backgroundColor);
                    margin: 0;
                    padding: 20px;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 16px 0;
                    font-size: \(tableFontSize)px;
                }
                th, td {
                    border: 1px solid \(borderColor);
                    padding: 8px 12px;
                    text-align: left;
                }
                th {
                    background-color: \(headerBgColor);
                    font-weight: 600;
                }
                tr:nth-child(even) {
                    background-color: \(isDarkMode ? "#252525" : "#FAFAFA");
                }
                h1 { font-size: \(h1Size)px; margin: 24px 0 16px 0; font-weight: 600; }
                h2 { font-size: \(h2Size)px; margin: 24px 0 16px 0; font-weight: 600; }
                h3 { font-size: \(h3Size)px; margin: 20px 0 14px 0; font-weight: 600; }
                h4 { font-size: \(h4Size)px; margin: 18px 0 12px 0; font-weight: 600; }
                h5 { font-size: \(h5Size)px; margin: 16px 0 10px 0; font-weight: 600; }
                h6 { font-size: \(h6Size)px; margin: 14px 0 8px 0; font-weight: 600; }
                p { margin: 12px 0; }
                p:empty { margin: 0; }
                ul, ol {
                    margin: 12px 0;
                    padding-left: 1.5em;
                }
                ul ul, ul ol, ol ul, ol ol {
                    margin: 2px 0;
                }
                li {
                    margin: 4px 0;
                }
                code {
                    background-color: \(isDarkMode ? "#2D2D2D" : "#F0F0F0");
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-family: \(monoFontStack);
                    font-size: \(codeFontSize)px;
                }
                pre {
                    background-color: \(isDarkMode ? "#2D2D2D" : "#F5F5F5");
                    padding: 16px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 16px 0;
                }
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                blockquote {
                    border-left: 4px solid \(borderColor);
                    margin: 12px 0;
                    padding-left: 16px;
                    color: \(isDarkMode ? "#AAAAAA" : "#666666");
                }
                .callout {
                    border-left-color: \(isDarkMode ? "#6B9BFF" : "#0066CC");
                    background: \(isDarkMode ? "rgba(107, 155, 255, 0.08)" : "rgba(0, 102, 204, 0.06)");
                    border-radius: 8px;
                    padding: 12px 14px;
                    color: \(textColor);
                }
                .callout-title {
                    font-weight: 700;
                    margin-bottom: 6px;
                }
                .callout-body {
                    color: \(textColor);
                }
                a {
                    color: \(isDarkMode ? "#6B9BFF" : "#0066CC");
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                a.wikilink {
                    font-weight: 500;
                }
                .embed {
                    display: inline-block;
                    padding: 2px 8px;
                    border-radius: 999px;
                    background-color: \(isDarkMode ? "#2A2A2A" : "#EFEFEF");
                    color: \(textColor);
                }
                .task-list {
                    list-style: none;
                    padding-left: 0;
                }
                .task-item {
                    display: flex;
                    align-items: baseline;
                    gap: 8px;
                }
                .task-item input[type="checkbox"] {
                    accent-color: \(isDarkMode ? "#6B9BFF" : "#0066CC");
                    cursor: pointer;
                    width: 14px;
                    height: 14px;
                    flex-shrink: 0;
                    margin-top: 2px;
                }
                hr {
                    border: none;
                    border-top: 1px solid \(borderColor);
                    margin: 24px 0;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                    display: block;
                    margin: 8px 0;
                }
                strong { font-weight: 600; }
                em { font-style: italic; }
                del { text-decoration: line-through; }
                \(SyntaxHighlightTheme.css(forDarkMode: isDarkMode))
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}
