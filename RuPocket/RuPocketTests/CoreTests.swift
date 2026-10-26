import XCTest
@testable import RuPocket

final class CoreTests: XCTestCase {
    func testTorrentAndNonTorrentResponses() {
        XCTAssertTrue(TorrentValidator.isTorrent(Data("d4:infod4:name4:test6:lengthi1eee".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("<html>Войдите в аккаунт</html>".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("d4:info4:teste".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("d4:infodeeTRAILING".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("d4:infod4:name999999999:xee".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("d4:infod1:xi-0eee".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("d4:infode4:infodee".utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data("d4:infod1:xi01eee".utf8)))
    }

    func testBinaryPiecesAndNestedFiles() {
        var data = Data("d4:infod5:filesld6:lengthi1e4:pathl1:aeee4:name1:x6:pieces20:".utf8)
        data.append(Data(repeating: 0xff, count: 20))
        data.append(Data("ee".utf8))
        XCTAssertTrue(TorrentValidator.isTorrent(data))
    }

    func testDepthAndLengthLimits() {
        XCTAssertFalse(TorrentValidator.isTorrent(Data(("d4:info" + String(repeating: "d1:x", count: 70) + "0:" + String(repeating: "e", count: 71)).utf8)))
        XCTAssertFalse(TorrentValidator.isTorrent(Data()))
        XCTAssertFalse(TorrentValidator.isTorrent(Data(repeating: 100, count: TorrentValidator.maximumBytes + 1)))
    }

    func testDomainBoundary() {
        for raw in ["https://rutracker.org/forum/index.php", "https://dl.rutracker.org/forum/dl.php?t=1"] {
            XCTAssertTrue(SitePolicy.isTrusted(URL(string: raw)!))
        }
        for raw in ["https://rutracker.org.evil.example/", "https://evilrutracker.org/", "http://rutracker.org/", "https://user:pass@rutracker.org/", "https://rutracker.org:444/"] {
            XCTAssertFalse(SitePolicy.isTrusted(URL(string: raw)!))
        }
    }

    func testFilenameSanitization() {
        XCTAssertEqual(SitePolicy.safeFilename("../../film.torrent"), "film.torrent")
        XCTAssertEqual(SitePolicy.safeFilename("..\\..\\film.torrent"), "film.torrent")
        XCTAssertEqual(SitePolicy.safeFilename(".hidden"), "hidden.torrent")
        XCTAssertEqual(SitePolicy.safeFilename(""), "Раздача.torrent")
        XCTAssertFalse(SitePolicy.safeFilename("a\nb").contains("\n"))
    }
}
