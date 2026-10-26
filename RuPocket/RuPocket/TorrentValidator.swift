import Foundation

/// Bounded bencode validation rejects HTML login and error responses saved as torrents.
enum TorrentValidator {
    static let maximumBytes = 20 * 1024 * 1024

    static func isTorrent(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumBytes else { return false }
        var parser = Parser(bytes: Array(data))
        return parser.parseTorrent()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var budget = 1_000_000

        mutating func string() -> ArraySlice<UInt8>? {
            let start = index
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
            guard index > start, index < bytes.count, bytes[index] == 58,
                  index - start <= 9,
                  !(index - start > 1 && bytes[start] == 48),
                  let length = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else { return nil }
            index += 1
            guard length <= bytes.count - index else { return nil }
            let result = bytes[index..<(index + length)]
            index += length
            return result
        }

        mutating func value(depth: Int) -> Bool {
            budget -= 1
            guard depth < 64, index < bytes.count, budget > 0 else { return false }
            switch bytes[index] {
            case 105: // integer
                index += 1
                let start = index
                if index < bytes.count, bytes[index] == 45 { index += 1 }
                let digits = index
                while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
                guard index > digits, index < bytes.count, bytes[index] == 101,
                      !(index - digits > 1 && bytes[digits] == 48),
                      !(digits > start && bytes[digits] == 48) else { return false }
                index += 1
                return true
            case 108, 100: // list or dictionary
                let dictionary = bytes[index] == 100
                index += 1
                while index < bytes.count, bytes[index] != 101 {
                    if dictionary && string() == nil { return false }
                    if !value(depth: depth + 1) { return false }
                }
                guard index < bytes.count else { return false }
                index += 1
                return true
            case 48...57: return string() != nil
            default: return false
            }
        }

        mutating func parseTorrent() -> Bool {
            guard bytes.first == 100 else { return false }
            index = 1
            var foundInfo = false
            while index < bytes.count, bytes[index] != 101 {
                guard let key = string() else { return false }
                let isInfo = key.elementsEqual([105, 110, 102, 111])
                if isInfo {
                    guard !foundInfo, index < bytes.count, bytes[index] == 100 else { return false }
                    foundInfo = true
                }
                guard value(depth: 1) else { return false }
            }
            return foundInfo && index == bytes.count - 1 && bytes[index] == 101
        }
    }
}
