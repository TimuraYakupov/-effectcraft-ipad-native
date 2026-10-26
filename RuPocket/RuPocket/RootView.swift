import SwiftUI
import WebKit

private enum Panel: String, Identifiable {
    case search, bookmarks, downloads, about
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var browser: BrowserModel
    @State private var panel: Panel?
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 14) {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left").frame(width: 32, height: 40) }
                    .disabled(!browser.canGoBack).accessibilityLabel("Назад")
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right").frame(width: 32, height: 40) }
                    .disabled(!browser.canGoForward).accessibilityLabel("Вперёд")
                Text(browser.title).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Button { browser.toggleBookmark() } label: {
                    Image(systemName: browser.isBookmarked ? "bookmark.fill" : "bookmark").frame(width: 38, height: 40)
                }.disabled(browser.currentURL == nil).accessibilityLabel(browser.isBookmarked ? "Удалить из избранного" : "В избранное")
            }.padding(.horizontal, 12).background(.white)

            GeometryReader { geometry in
                Color.clear.overlay(alignment: .leading) {
                    Rectangle().fill(Color.accentColor).frame(width: max(0, geometry.size.width * browser.progress))
                        .opacity(browser.isLoading ? 1 : 0).animation(.easeOut(duration: 0.18), value: browser.progress)
                }
            }.frame(height: 2)

            ZStack {
                BrowserView(webView: browser.webView)
                if let error = browser.pageError {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Сайт не открылся", text: error) {
                        Button("Повторить") { browser.open(browser.currentURL ?? SitePolicy.home) }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGroupedBackground))
                }
            }

            if browser.torrentURL != nil || browser.downloadCount > 0 {
                HStack(spacing: 12) {
                    Button { browser.startTorrentDownload() } label: {
                        HStack(spacing: 8) {
                            if browser.downloadCount > 0 { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.down.document.fill") }
                            Text(browser.downloadCount > 0 ? "Скачивание…" : "Скачать .torrent").fontWeight(.semibold)
                        }.frame(maxWidth: .infinity).padding(.vertical, 13)
                    }.buttonStyle(.borderedProminent).disabled(browser.downloadCount > 0)
                    if browser.magnet != nil {
                        Menu {
                            Button("Скопировать magnet", systemImage: "doc.on.doc") { browser.copyMagnet() }
                            Button("Поделиться magnet", systemImage: "square.and.arrow.up") { browser.shareMagnet() }
                        } label: { Image(systemName: "link").font(.title3).frame(width: 46, height: 48).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }
                        .accessibilityLabel("Magnet-ссылка")
                    }
                }.padding(12).background(.white)
            }
            Divider()
            HStack(spacing: 0) {
                tab("Разделы", symbol: "square.grid.2x2") { browser.open(SitePolicy.home) }
                tab("Поиск", symbol: "magnifyingglass") { panel = .search }
                tab("Избранное", symbol: "bookmark") { panel = .bookmarks }
                tab("Файлы", symbol: "arrow.down.circle", badge: browser.downloads.count) { browser.reloadDownloads(); panel = .downloads }
            }.padding(.top, 8).padding(.bottom, 6).background(.white)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $panel) { selected in
            switch selected {
            case .search: SearchPanel().environmentObject(browser)
            case .bookmarks: BookmarksPanel().environmentObject(browser)
            case .downloads: DownloadsPanel().environmentObject(browser)
            case .about: AboutPanel()
            }
        }
        .background(ActivityPresenter(item: $browser.sharedItem).frame(width: 0, height: 0))
        .alert("RuPocket", isPresented: Binding(get: { browser.alertMessage != nil }, set: { if !$0 { browser.alertMessage = nil } })) {
            Button("Понятно", role: .cancel) { browser.alertMessage = nil }
        } message: { Text(browser.alertMessage ?? "") }
        .confirmationDialog("Открыть внешний сайт в Safari?", isPresented: Binding(get: { browser.externalURL != nil }, set: { if !$0 { browser.externalURL = nil } }), titleVisibility: .visible) {
            if let url = browser.externalURL {
                Button("Открыть \(url.host ?? "ссылку")") { UIApplication.shared.open(url); browser.externalURL = nil }
            }
            Button("Отмена", role: .cancel) { browser.externalURL = nil }
        }
        .confirmationDialog("Удалить данные входа на сайте?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Удалить данные входа", role: .destructive) { browser.clearSession() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white).frame(width: 43, height: 43)
                .background(LinearGradient(colors: [Color(red: 0.16, green: 0.48, blue: 0.98), Color(red: 0.08, green: 0.32, blue: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text("RuPocket").font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.09, green: 0.15, blue: 0.23))
                Text("RuTracker под рукой").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { panel = .search } label: { Image(systemName: "magnifyingglass").font(.title3).frame(width: 40, height: 44) }.accessibilityLabel("Поиск раздач")
            Menu {
                Button("Войти в RuTracker", systemImage: "person.crop.circle") { browser.open(URL(string: "https://rutracker.org/forum/login.php")!) }
                Button(browser.isLoading ? "Остановить" : "Обновить", systemImage: browser.isLoading ? "xmark" : "arrow.clockwise") {
                    if browser.isLoading { browser.webView.stopLoading(); browser.isLoading = false }
                    else { browser.webView.reload() }
                }
                Toggle("Мобильный вид", isOn: Binding(get: { browser.mobileLayout }, set: { browser.setMobileLayout($0) }))
                if let url = browser.currentURL {
                    ShareLink(item: url) { Label("Поделиться страницей", systemImage: "square.and.arrow.up") }
                    Button("Открыть в Safari", systemImage: "safari") { UIApplication.shared.open(url) }
                }
                Divider()
                Button("О приложении", systemImage: "info.circle") { panel = .about }
                Button("Удалить данные входа", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 36, height: 44) }.accessibilityLabel("Меню")
        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8).background(.white)
    }

    private func tab(_ title: String, symbol: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 { Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: 5, y: -1) }
                    }
                Text(title).font(.system(size: 10, weight: .medium))
            }.frame(maxWidth: .infinity).frame(minHeight: 44)
        }.foregroundStyle(Color(red: 0.30, green: 0.39, blue: 0.52))
    }
}

private struct BrowserView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct SearchPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastSearch") private var query = ""
    @AppStorage("searchSort") private var order = 10
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Что найти") {
                    TextField("Название раздачи", text: $query).focused($focused).submitLabel(.search)
                        .autocorrectionDisabled().onSubmit(runSearch)
                }
                Section("Порядок результатов") {
                    Picker("Сортировка", selection: $order) {
                        Text("Больше сидов").tag(10)
                        Text("Сначала новые").tag(1)
                        Text("По размеру").tag(7)
                        Text("По названию").tag(2)
                    }
                }
                Section {
                    Button(action: runSearch) { Label("Найти раздачи", systemImage: "magnifyingglass").frame(maxWidth: .infinity) }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: { Text("Для поиска может понадобиться вход в аккаунт RuTracker. Фильтры категорий доступны на странице поиска сайта.") }
            }.navigationTitle("Поиск").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
                .onAppear { focused = true }
        }.presentationDetents([.medium, .large])
    }
    private func runSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        browser.search(query, order: order); dismiss()
    }
}

private struct BookmarksPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if browser.bookmarks.isEmpty {
                    EmptyState(symbol: "bookmark", title: "Сохранённые страницы", text: "Открой раздачу и нажми значок закладки вверху.") { EmptyView() }
                } else {
                    List {
                        ForEach(browser.bookmarks) { item in
                            Button { browser.open(item.url); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(3)
                                    Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }.swipeActions { Button("Удалить", role: .destructive) { browser.removeBookmark(item) } }
                        }
                    }
                }
            }.navigationTitle("Избранное").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct DownloadsPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if browser.downloads.isEmpty {
                    EmptyState(symbol: "arrow.down.document", title: "Здесь будут .torrent", text: "Открой раздачу и нажми «Скачать .torrent». Затем сохрани файл в «Файлы» или передай в другое приложение.") { EmptyView() }
                } else {
                    List {
                        Section {
                            ForEach(browser.downloads) { item in
                                ShareLink(item: item.url) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.zipper").font(.title2).foregroundStyle(Color.accentColor).frame(width: 34)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).font(.body.weight(.medium)).lineLimit(3).foregroundStyle(.primary)
                                            Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file) + " · " + item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "square.and.arrow.up").foregroundStyle(Color.accentColor)
                                    }.padding(.vertical, 5)
                                }.swipeActions { Button("Удалить", role: .destructive) { browser.deleteDownload(item) } }
                            }
                        } footer: { Text("Это торрент-файлы с описанием раздач. Их содержимое загружает отдельный торрент-клиент.") }
                    }
                }
            }.navigationTitle("Файлы").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct AboutPanel: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Версия", value: "0.1.0 · прототип")
                    Text("RuPocket — неофициальный клиент RuTracker для iPhone. Показывает сайт с мобильной вёрсткой и сохраняет .torrent.")
                }
                Section("Аккаунт") {
                    Text("Вход выполняется на сайте RuTracker. Сессией управляет WebKit на этом устройстве. В приложении нет собственного сервера и аналитики.")
                }
                Section("Первая проверка") {
                    Text("Мобильная адаптация ещё требует проверки на действующем сайте. Если страница выглядит неправильно, отключи «Мобильный вид» в меню.")
                }
            }.navigationTitle("О RuPocket").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct EmptyState<Action: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder let action: () -> Action
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 46, weight: .light)).foregroundStyle(Color.accentColor).padding(.bottom, 4)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            action()
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Presents above the currently open panel, so completed downloads can be shared anywhere.
private struct ActivityPresenter: UIViewControllerRepresentable {
    @Binding var item: SharedItem?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let item, context.coordinator.presentedID != item.id else { return }
        context.coordinator.presentedID = item.id
        let binding = $item
        DispatchQueue.main.async {
            guard let window = controller.view.window, var top = window.rootViewController else {
                context.coordinator.presentedID = nil
                return
            }
            while let presented = top.presentedViewController { top = presented }
            let activity = UIActivityViewController(activityItems: item.items, applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in binding.wrappedValue = nil }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            }
            top.present(activity, animated: true)
        }
    }
    final class Coordinator { var presentedID: UUID? }
}
