import SwiftUI
import WebKit

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let webView: WKWebView
    @Published var title = "RuPocket"
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress = 0.0
    @Published var isLoading = false
    @Published var pageError: String?
    @Published var alertMessage: String?
    @Published var sharedItem: SharedItem?
    @Published var externalURL: URL?
    @Published var torrentURL: URL?
    @Published var magnet: String?
    @Published var downloadCount = 0
    @Published var bookmarks: [SavedTopic] = []
    @Published var downloads: [LocalTorrent] = []
    @Published var mobileLayout = true
    @Published var searchRequest = UUID()

    private var observations: [NSKeyValueObservation] = []
    private var pendingSearch: (query: String, order: Int)?
    private struct Transfer {
        let download: WKDownload
        var temporaryURL: URL?
        var filename = "Раздача.torrent"
    }
    private var transfers: [ObjectIdentifier: Transfer] = [:]
    private let storageKey = "RuPocket.savedTopics.v1"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if UserDefaults.standard.integer(forKey: "layoutRevision") < 2 {
            UserDefaults.standard.set(true, forKey: "mobileLayout")
            UserDefaults.standard.set(2, forKey: "layoutRevision")
        }
        let useMobileLayout = UserDefaults.standard.object(forKey: "mobileLayout") as? Bool ?? true
        WebPageAdapter.install(on: config, enabled: useMobileLayout)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        mobileLayout = useMobileLayout
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([SavedTopic].self, from: data) {
            bookmarks = saved.filter { SitePolicy.isTrusted($0.url) }
        }
        webView.configuration.userContentController.add(WeakScriptHandler(self), name: "rupocket")
        if WebPageAdapter.source(enabled: useMobileLayout) == nil {
            alertMessage = "Не найдены файлы мобильной вёрстки. Проверь сборку приложения."
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemGroupedBackground
        webView.scrollView.keyboardDismissMode = .onDrag
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
            DispatchQueue.main.async { self?.progress = web.estimatedProgress }
        })
        observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] web, _ in
            DispatchQueue.main.async { self?.canGoBack = web.canGoBack }
        })
        observations.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] web, _ in
            DispatchQueue.main.async { self?.canGoForward = web.canGoForward }
        })
        reloadDownloads()
        open(SitePolicy.home)
    }

    static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let string = String(data: data, encoding: .utf8) else { return "null" }
        return string
    }

    func open(_ url: URL) {
        guard SitePolicy.isTrusted(url) else { return }
        pageError = nil
        webView.load(URLRequest(url: url))
    }

    func search(_ query: String, order: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingSearch = (trimmed, order)
        open(URL(string: "https://rutracker.org/forum/tracker.php")!)
    }

    func setMobileLayout(_ value: Bool) {
        mobileLayout = value
        UserDefaults.standard.set(value, forKey: "mobileLayout")
        webView.evaluateJavaScript("window.RuPocket?.setEnabled(\(value ? "true" : "false"))", completionHandler: nil)
    }

    var isBookmarked: Bool {
        guard let url = currentURL else { return false }
        return bookmarks.contains { Self.topicKey($0.url) == Self.topicKey(url) }
    }

    private static func topicKey(_ url: URL) -> String {
        if url.lastPathComponent == "viewtopic.php",
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value {
            return "topic:" + id
        }
        return url.absoluteString
    }

    func toggleBookmark() {
        guard let url = currentURL, SitePolicy.isTrusted(url) else { return }
        if let index = bookmarks.firstIndex(where: { Self.topicKey($0.url) == Self.topicKey(url) }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(SavedTopic(title: title, url: url, date: Date()), at: 0)
        }
        saveBookmarks()
    }

    func removeBookmark(_ item: SavedTopic) {
        bookmarks.removeAll { $0.id == item.id }
        saveBookmarks()
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    func shareMagnet() {
        guard let magnet else { return }
        sharedItem = SharedItem(items: [magnet])
    }

    func copyMagnet() {
        guard let magnet else { return }
        UIPasteboard.general.string = magnet
        alertMessage = "Magnet-ссылка скопирована."
    }

    func startTorrentDownload() {
        guard let url = torrentURL, SitePolicy.isTrusted(url), transfers.isEmpty, downloadCount == 0 else { return }
        downloadCount = 1
        var request = URLRequest(url: url)
        if let currentURL { request.setValue(currentURL.absoluteString, forHTTPHeaderField: "Referer") }
        webView.startDownload(using: request) { [weak self] download in self?.register(download) }
    }

    private func register(_ download: WKDownload) {
        transfers[ObjectIdentifier(download)] = Transfer(download: download)
        downloadCount = transfers.count
        download.delegate = self
    }

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    func reloadDownloads() {
        let root = documents.appendingPathComponent("Torrents", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
            downloads = []; return
        }
        downloads = enumerator.compactMap { item -> LocalTorrent? in
            guard let url = item as? URL, url.pathExtension.lowercased() == "torrent",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            return LocalTorrent(url: url, date: values.creationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    func deleteDownload(_ item: LocalTorrent) {
        do {
            try FileManager.default.removeItem(at: item.url)
            try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
            reloadDownloads()
        } catch { alertMessage = error.localizedDescription }
    }

    func clearSession() {
        pendingSearch = nil
        webView.stopLoading()
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async { self?.open(SitePolicy.home) }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true; pageError = nil; torrentURL = nil; magnet = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentURL = webView.url
        if let raw = webView.title, !raw.isEmpty { title = raw }
        if let source = WebPageAdapter.source(enabled: mobileLayout) {
            webView.evaluateJavaScript(source, completionHandler: nil)
        }
        if webView.url?.lastPathComponent == "tracker.php", let search = pendingSearch {
            pendingSearch = nil
            let script = "window.RuPocket?.search(\(Self.json(search.query)), \(search.order)) ?? false"
            webView.evaluateJavaScript(script) { [weak self] value, error in
                if error != nil || (value as? Bool) != true {
                    self?.alertMessage = "Форма поиска недоступна. Войди в аккаунт через меню и повтори поиск."
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    private func navigationFailed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled,
              (error as NSError).code != 102 else { return }
        isLoading = false
        pageError = "Не удалось открыть RuTracker. Проверь подключение и доступность сайта в своей сети."
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "magnet" {
            sharedItem = SharedItem(items: [url.absoluteString])
            decisionHandler(.cancel); return
        }
        // Restrict top-level browsing, while allowing subframes to use WebKit's normal policy.
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard SitePolicy.isTrusted(url) else {
            if ["https", "http"].contains(url.scheme?.lowercased() ?? ""), action.navigationType == .linkActivated { externalURL = url }
            decisionHandler(.cancel); return
        }
        if action.targetFrame == nil {
            open(url); decisionHandler(.cancel); return
        }
        if action.shouldPerformDownload { decisionHandler(.download) }
        else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame && (response.response.mimeType == "application/x-bittorrent" || !response.canShowMIMEType) {
            decisionHandler(.download)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { register(download) }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url {
            if SitePolicy.isTrusted(url) { open(url) }
            else if ["http", "https"].contains(url.scheme ?? "") { externalURL = url }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        alertMessage = message
        completionHandler()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let origin = message.frameInfo.request.url, SitePolicy.isTrusted(origin),
              let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "search" { searchRequest = UUID(); return }
        guard body["type"] as? String == "page" else { return }
        if let pageTitle = body["title"] as? String, !pageTitle.isEmpty { title = pageTitle }
        currentURL = webView.url
        if let raw = body["torrentURL"] as? String, let url = URL(string: raw), SitePolicy.isTrusted(url), url.lastPathComponent == "dl.php" {
            torrentURL = url
        } else { torrentURL = nil }
        if let raw = body["magnet"] as? String, raw.hasPrefix("magnet:?") { magnet = raw }
        else { magnet = nil }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let id = ObjectIdentifier(download)
        guard transfers[id] != nil,
              let url = response.url, SitePolicy.isTrusted(url),
              response.expectedContentLength <= Int64(TorrentValidator.maximumBytes) else {
            completionHandler(nil); failTransfer(download, message: "Ответ сервера недоступен или слишком большой для .torrent."); return
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            completionHandler(nil); failTransfer(download, message: "Сервер вернул ошибку \(http.statusCode). Попробуй открыть раздачу заново."); return
        }
        do {
            let directory = documents.appendingPathComponent(".incoming", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(UUID().uuidString)
            transfers[id]?.temporaryURL = destination
            transfers[id]?.filename = SitePolicy.safeFilename(suggestedFilename)
            completionHandler(destination)
        } catch { completionHandler(nil); failTransfer(download, message: error.localizedDescription) }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(request.url.map(SitePolicy.isTrusted) == true ? .allow : .cancel)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = transfers[ObjectIdentifier(download)], let temporary = transfer.temporaryURL else {
            failTransfer(download, message: "Не найден скачанный файл."); return
        }
        defer { transfers.removeValue(forKey: ObjectIdentifier(download)); downloadCount = transfers.count; isLoading = false }
        do {
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= TorrentValidator.maximumBytes,
                  TorrentValidator.isTorrent(try Data(contentsOf: temporary)) else {
                try? FileManager.default.removeItem(at: temporary)
                alertMessage = "Вместо .torrent сервер вернул другую страницу. Войди в аккаунт и повтори скачивание."
                return
            }
            let directory = documents.appendingPathComponent("Torrents/" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let finalURL = directory.appendingPathComponent(transfer.filename)
            try FileManager.default.moveItem(at: temporary, to: finalURL)
            reloadDownloads()
            sharedItem = SharedItem(items: [finalURL])
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            alertMessage = error.localizedDescription
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { failTransfer(download, message: "Не удалось скачать .torrent: " + error.localizedDescription) }

    private func failTransfer(_ download: WKDownload, message: String) {
        if let temporary = transfers.removeValue(forKey: ObjectIdentifier(download))?.temporaryURL { try? FileManager.default.removeItem(at: temporary) }
        downloadCount = transfers.count
        isLoading = false
        alertMessage = message
    }
}
