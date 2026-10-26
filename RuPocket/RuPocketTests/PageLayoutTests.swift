import XCTest
import WebKit
import UIKit
@testable import RuPocket

@MainActor
final class PageLayoutTests: XCTestCase {
    private final class NavigationProbe: NSObject, WKNavigationDelegate {
        let loaded: XCTestExpectation
        init(_ loaded: XCTestExpectation) { self.loaded = loaded }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    }

    private func render(_ html: String, path: String) async throws -> (WKWebView, UIWindow) {
        let config = WKWebViewConfiguration()
        WebPageAdapter.install(on: config, enabled: true)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else { window = UIWindow(frame: web.frame) }
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(web)
        window.isHidden = false
        let loaded = expectation(description: "WebKit loaded fixture")
        let probe = NavigationProbe(loaded)
        web.navigationDelegate = probe
        web.loadHTMLString(html, baseURL: URL(string: "https://rutracker.org/forum/" + path)!)
        await fulfillment(of: [loaded], timeout: 20)
        web.navigationDelegate = nil
        return (web, window)
    }

    func testDesktopPortalBecomesFullWidthPhoneCards() async throws {
        let html = """
        <!doctype html><html><head><title>RuTracker.org</title><style>
        body{min-width:980px;font:11px Arial}#portal{width:1100px;table-layout:fixed}
        #sidebar{width:180px}.news{width:400px}table{font-size:11px}
        </style></head><body><table id="portal"><tr>
        <td id="sidebar"><a href="index.php?c=2">Кино, видео и ТВ</a>
        <a href="viewforum.php?f=7">Фильмы в высоком качестве</a>
        <a href="viewforum.php?f=8">Музыка и аудио</a></td>
        <td class="news"><h2>Авторские раздачи</h2><p>Длинная настольная колонка</p></td>
        <td width="400"><img width="400" alt="Реклама"></td></tr></table></body></html>
        """
        let (web, window) = try await render(html, path: "index.php")
        defer { window.isHidden = true }
        let result = try await web.evaluateJavaScript("""
        (() => { const c=document.querySelector('#rp-app .rp-card'); return {
          cards:document.querySelectorAll('#rp-app .rp-card').length,
          viewport:innerWidth, scroll:document.documentElement.scrollWidth,
          width:c?.getBoundingClientRect().width || 0,
          font:parseFloat(getComputedStyle(document.querySelector('.rp-card-title')).fontSize),
          original:getComputedStyle(document.getElementById('portal')).display
        }; })()
        """) as! [String: Any]
        XCTAssertEqual(result["cards"] as? Int, 3)
        let viewport = (result["viewport"] as? Double) ?? 0
        XCTAssertGreaterThan(viewport, 300)
        XCTAssertLessThanOrEqual(viewport, 430)
        XCTAssertLessThanOrEqual((result["scroll"] as? Double) ?? 9999, viewport + 1)
        XCTAssertGreaterThanOrEqual((result["width"] as? Double) ?? 0, viewport - 34)
        XCTAssertGreaterThanOrEqual((result["font"] as? Double) ?? 0, 17)
        XCTAssertEqual(result["original"] as? String, "none")
        let image = try await web.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: image)
        attachment.name = "RuPocket phone catalogue"
        attachment.lifetime = .keepAlways
        add(attachment)
        let png = try XCTUnwrap(image.pngData())
        try png.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LayoutCatalogue.png"))
        try await web.evaluateJavaScript("window.RuPocket.setEnabled(false)")
        let restored = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('portal')).display") as? String
        XCTAssertNotEqual(restored, "none")
    }

    func testSearchResultsHaveReadableTitlesAndMetadata() async throws {
        let html = """
        <!doctype html><html><head><title>Поиск</title><style>body{min-width:1000px}table{width:1200px;font:10px Arial}</style></head>
        <body><table><tr id="trs-tr-4"><td><a class="tLink" href="viewtopic.php?t=4">Тестовая раздача с длинным русским названием</a></td>
        <td class="tor-size">1.5 GB</td><td><b class="seedmed">123</b></td></tr></table></body></html>
        """
        let (web, window) = try await render(html, path: "tracker.php")
        defer { window.isHidden = true }
        let result = try await web.evaluateJavaScript("""
        ({width:innerWidth, scroll:document.documentElement.scrollWidth,
          title:document.querySelector('.rp-card-title')?.textContent,
          font:parseFloat(getComputedStyle(document.querySelector('.rp-card-title')).fontSize),
          seeds:document.querySelector('.rp-seeds')?.textContent})
        """) as! [String: Any]
        XCTAssertTrue((result["title"] as? String)?.contains("Тестовая раздача") == true)
        XCTAssertTrue((result["seeds"] as? String)?.contains("123") == true)
        XCTAssertGreaterThanOrEqual((result["font"] as? Double) ?? 0, 17)
        XCTAssertLessThanOrEqual((result["scroll"] as? Double) ?? 9999, ((result["width"] as? Double) ?? 0) + 1)
    }
}
