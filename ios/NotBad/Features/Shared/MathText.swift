import SwiftUI
import WebKit

/// 显示混排了 $...$ 公式的文字（题干、答案、解析），用打包在 App 里的 KaTeX 离线渲染。
/// 不含公式的文字直接用 Text，省掉 WebView 的开销。
struct MathText: View {
    let text: String

    @State private var height: CGFloat = 24

    static func containsMath(_ text: String) -> Bool {
        text.contains("$") || text.contains("\\(") || text.contains("\\[")
    }

    var body: some View {
        if Self.containsMath(text) {
            MathWebView(text: text, height: $height)
                .frame(height: height)
        } else {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// 列表等地方用的纯文字预览：去掉公式定界符。
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "$", with: "")
    }
}

private struct MathWebView: UIViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "height")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.pendingText = text
        if let url = Bundle.main.url(forResource: "math", withExtension: "html", subdirectory: "KaTeX") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.show(text, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var pendingText: String?
        private var loaded = false
        private var shownText: String?

        init(height: Binding<CGFloat>) { self.height = height }

        func show(_ text: String, in webView: WKWebView) {
            guard loaded else {
                pendingText = text
                return
            }
            guard text != shownText else { return }
            shownText = text
            // 用 JSON 编码安全地把任意文字传进 JS
            guard let data = try? JSONEncoder().encode([text]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("render(\(json)[0])")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let text = pendingText {
                pendingText = nil
                show(text, in: webView)
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? Double ?? (message.body as? Int).map(Double.init) else { return }
            let newHeight = max(20, CGFloat(value) + 4)
            if abs(height.wrappedValue - newHeight) > 1 {
                height.wrappedValue = newHeight
            }
        }
    }
}
