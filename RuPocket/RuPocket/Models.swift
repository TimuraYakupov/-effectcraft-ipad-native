import Foundation

struct SavedTopic: Codable, Identifiable {
    var id: String { url.absoluteString }
    let title: String
    let url: URL
    let date: Date
}

struct SharedItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct LocalTorrent: Identifiable {
    var id: URL { url }
    let url: URL
    let date: Date
    let bytes: Int64
    var title: String { url.deletingPathExtension().lastPathComponent }
}

enum SitePolicy {
    static let home = URL(string: "https://rutracker.org/forum/index.php")!
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return host == "rutracker.org" || host.hasSuffix(".rutracker.org")
    }

    static func safeFilename(_ proposed: String) -> String {
        let name = proposed.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: ":/\\"))
        var clean = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix(".") { clean.removeFirst() }
        if clean.isEmpty { clean = "Раздача" }
        clean = String(clean.prefix(140))
        if !clean.lowercased().hasSuffix(".torrent") { clean += ".torrent" }
        return clean
    }
}
