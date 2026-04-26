import SwiftUI
import WebKit

@MainActor
final class MiniBrowserController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var urlText: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
    }

    func load(_ input: String) {
        guard let normalized = MiniBrowserURLNormalizer.normalizedURLString(from: input),
              let url = URL(string: normalized) else { return }
        urlText = normalized
        webView.load(URLRequest(url: url))
    }

    func reload() {
        webView.reload()
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        syncState(with: webView)
        NSLog("[Browser] start %@", webView.url?.absoluteString ?? "nil")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        syncState(with: webView)
        NSLog("[Browser] finish %@", webView.url?.absoluteString ?? "nil")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        syncState(with: webView)
        NSLog("[Browser] fail %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        syncState(with: webView)
        NSLog("[Browser] provisional fail %@", error.localizedDescription)
    }

    private func syncState(with webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let currentURL = webView.url?.absoluteString, !currentURL.isEmpty {
            urlText = currentURL
        }
    }
}

struct MiniBrowserWebView: NSViewRepresentable {
    @ObservedObject var controller: MiniBrowserController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct MiniBrowserPaneView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var controller = MiniBrowserController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: controller.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canGoBack)
                .help("Go Back")

                Button(action: controller.goForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canGoForward)
                .help("Go Forward")

                Button(action: controller.reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Reload")

                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(SynapseTheme.textMuted)

                    TextField("Enter URL", text: $controller.urlText, onCommit: {
                        controller.load(controller.urlText)
                    })
                    .font(.system(size: 12, design: .rounded))
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)

                    if controller.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SynapseTheme.panelElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SynapseTheme.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SynapseTheme.panelElevated)

            Divider()
                .background(SynapseTheme.border)

            MiniBrowserWebView(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SynapseTheme.panel)
        }
        .background(SynapseTheme.panel)
        .onAppear {
            if controller.urlText.isEmpty {
                let startupURL = appState.settings.browserStartupURL
                if !startupURL.isEmpty {
                    controller.load(startupURL)
                }
            }
        }
    }
}
