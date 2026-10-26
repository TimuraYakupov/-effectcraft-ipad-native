import Foundation
import WebKit

enum WebPageAdapter {
    static func source(enabled: Bool) -> String? {
        guard let jsURL = Bundle.main.url(forResource: "mobile", withExtension: "js"),
              let cssURL = Bundle.main.url(forResource: "mobile", withExtension: "css"),
              let js = try? String(contentsOf: jsURL, encoding: .utf8),
              let css = try? String(contentsOf: cssURL, encoding: .utf8),
              let data = try? JSONSerialization.data(withJSONObject: css, options: [.fragmentsAllowed]),
              let escapedCSS = String(data: data, encoding: .utf8) else { return nil }
        return """
        (function() {
            const origin = new URL(location.href === 'about:blank' ? document.baseURI : location.href);
            if (origin.protocol !== 'https:' || !(origin.hostname === 'rutracker.org' || origin.hostname.endsWith('.rutracker.org'))) return;
            let style = document.getElementById('rp-mobile-style');
            if (!style) { style = document.createElement('style'); style.id = 'rp-mobile-style'; document.head.appendChild(style); }
            style.textContent = \(escapedCSS);
            \(js)
            window.RuPocket?.setEnabled(\(enabled ? "true" : "false"));
        })();
        """
    }

    static func install(on configuration: WKWebViewConfiguration, enabled: Bool) {
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        if let source = source(enabled: enabled) {
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }
}
