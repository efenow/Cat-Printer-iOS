import SwiftUI
import WebKit

struct AppWebView: UIViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> LocalSchemeHandler {
        LocalSchemeHandler(api: model.apiService)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "catprinter")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false

        if let url = URL(string: "catprinter://app/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
