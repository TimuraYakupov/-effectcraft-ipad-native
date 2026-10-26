import SwiftUI

@main
struct RuPocketApp: App {
    @StateObject private var browser = BrowserModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(browser).preferredColorScheme(.light)
        }
    }
}
