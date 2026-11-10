import Foundation

struct SyncReport: Decodable, Sendable {
    struct Target: Decodable, Sendable {
        let name: String
    }

    struct Entry: Decodable, Identifiable, Sendable {
        let source: Track
        let status: String
        let targetID: String?
        let candidates: [Track]?

        enum CodingKeys: String, CodingKey {
            case source, status, candidates
            case targetID = "id"
        }

        var id: String { source.id }

        var statusLabel: String {
            switch status {
            case "matched": "已匹配"
            case "manual": "人工匹配"
            case "review": "待复核"
            case "missing": "未找到"
            case "unavailable": "无播放权限"
            case "pending": "待检索"
            case "error": "检索失败"
            case "skipped": "已跳过"
            default: status
            }
        }

        var isMatched: Bool { status == "matched" || status == "manual" }
        var needsReview: Bool { !isMatched && status != "skipped" }
    }

    struct Track: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let artist: String?
        let album: String?
        let duration: Double?
        let dateAdded: Date?

        enum CodingKeys: String, CodingKey {
            case id, title, artist, album, duration
            case dateAdded = "date_added"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            artist = try values.decodeIfPresent(String.self, forKey: .artist)
            album = try values.decodeIfPresent(String.self, forKey: .album)
            duration = try values.decodeIfPresent(Double.self, forKey: .duration)
            let timestamp = try values.decodeIfPresent(String.self, forKey: .dateAdded)
            dateAdded = timestamp.flatMap {
                (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0))
                    ?? (try? Date.ISO8601FormatStyle().parse($0))
            }
        }

        var durationLabel: String {
            guard let duration, duration.isFinite, duration >= 0, duration < Double(Int.max) else { return "—" }
            return Duration.seconds(Int(duration)).formatted(.time(pattern: .minuteSecond))
        }
    }

    let target: Target
    let entries: [Entry]
    let additions: Set<String>?

    static var location: URL {
        URL.applicationSupportDirectory
            .appending(path: "AM-NCM", directoryHint: .isDirectory)
            .appending(path: "netease-plan.json", directoryHint: .notDirectory)
    }

    @concurrent
    static func load() async throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: location))
    }
}
