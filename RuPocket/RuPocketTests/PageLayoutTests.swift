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
        window.makeKeyAndVisible()
        let loaded = expectation(description: "WebKit loaded fixture")
        let probe = NavigationProbe(loaded)
        web.navigationDelegate = probe
        web.loadHTMLString(html, baseURL: URL(string: "https://rutracker.org/forum/" + path)!)
        await fulfillment(of: [loaded], timeout: 45)
        withExtendedLifetime(probe) { web.navigationDelegate = nil }
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
        XCTAssertEqual(result["cards"] as? Int, 1)
        let viewport = (result["viewport"] as? Double) ?? 0
        XCTAssertGreaterThan(viewport, 300)
        XCTAssertLessThanOrEqual(viewport, 430)
        XCTAssertLessThanOrEqual((result["scroll"] as? Double) ?? 9999, viewport + 1)
        XCTAssertGreaterThanOrEqual((result["width"] as? Double) ?? 0, viewport - 34)
        XCTAssertGreaterThanOrEqual((result["font"] as? Double) ?? 0, 17)
        XCTAssertEqual(result["original"] as? String, "none")
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

    func testConsoleSectionShowsBothSubforumsAndPinnedTopics() async throws {
        let html = """
        <!doctype html><html><head><title>Игры для консолей</title></head><body>
        <div class="nav"><a href="viewforum.php?f=5">Игры для консолей</a></div>
        <table class="forumline"><tr><td><a class="forumlink" href="viewforum.php?f=10">PlayStation</a></td></tr>
        <tr><td><a class="forumlink" href="viewforum.php?f=11">Xbox</a></td></tr>
        <tr><td><a class="forumlink" href="viewforum.php?f=12">Nintendo</a></td></tr></table>
        <table class="forumline"><tr><td><a class="torTopic" href="viewtopic.php?t=1">Правила раздела</a></td></tr>
        <tr><td><a class="torTopic" href="viewtopic.php?t=2">Обсуждения</a></td></tr>
        <tr><td><a class="torTopic" href="viewtopic.php?t=3">Важная информация</a></td></tr></table>
        </body></html>
        """
        let (web, window) = try await render(html, path: "viewforum.php?f=5")
        defer { window.isHidden = true }
        let result = try await web.evaluateJavaScript("""
        ({forums:document.querySelectorAll('#rp-app .rp-forum-card').length,
          topics:document.querySelectorAll('#rp-app .rp-result').length,
          width:innerWidth, scroll:document.documentElement.scrollWidth})
        """) as! [String: Any]
        XCTAssertEqual(result["forums"] as? Int, 3)
        XCTAssertEqual(result["topics"] as? Int, 3)
        XCTAssertLessThanOrEqual((result["scroll"] as? Double) ?? 9999, ((result["width"] as? Double) ?? 0) + 1)
    }

    func testGlobalGroupsAreCollapsedUntilOpened() async throws {
        let html = """
        <!doctype html><html><head><title>RuTracker.org</title></head><body>
        <div class="cat_title">Игры</div><a href="viewforum.php?f=10">Игры для консолей</a>
        <div class="cat_title">Книги</div><a href="viewforum.php?f=20">Фантастика</a>
        </body></html>
        """
        let (web, window) = try await render(html, path: "index.php")
        defer { window.isHidden = true }
        let closed = try await web.evaluateJavaScript("""
        ({groups:document.querySelectorAll('#rp-app details').length,
          height:document.querySelector('#rp-app .rp-forum-card').getBoundingClientRect().height})
        """) as! [String: Any]
        XCTAssertEqual(closed["groups"] as? Int, 2)
        XCTAssertEqual((closed["height"] as? Double) ?? -1, 0)
        let expandedHeight = try await web.evaluateJavaScript("""
        (() => {document.querySelector('#rp-app details').open=true;
          return document.querySelector('#rp-app .rp-forum-card').getBoundingClientRect().height;})()
        """) as? Double
        XCTAssertGreaterThan(expandedHeight ?? 0, 44)
    }
}
