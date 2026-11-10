import Foundation

struct NetEaseTrack: Decodable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let artists: [String]?
    let album: String
    let duration: Double
}

struct AppleMusicImport {
    struct Candidate {
        let sourceID: String
        let catalogID: String
    }

    enum Failure: LocalizedError, Equatable {
        case authorization, busy, response(Int)
        var errorDescription: String? {
            switch self {
            case .authorization: "Apple Music 授权已失效，请在设置中重新登录。"
            case .busy: "Apple Music 暂时限制请求，请稍后重试。"
            case .response(let code): "Apple Music 暂时无法处理请求（\(code)）。"
            }
        }
    }

    private struct Collection: Decodable {
        let data: [Item]
    }

    private struct Item: Decodable {
        struct Attributes: Decodable {
            let name: String?
            let artistName: String?
            let albumName: String?
            let durationInMillis: Int?
            let isrc: String?
        }

        let id: String
        let attributes: Attributes?
        let relationships: [String: Collection]?
    }

    private struct Search: Decodable {
        let results: [String: Collection]
    }

    let session: AppleMusicSession

    static func connect(developer: String, user: String) async throws -> AppleMusicSession {
        guard developer.split(separator: ".").count == 3, !user.isEmpty,
              developer.count <= 8192, user.count <= 8192 else { throw Failure.authorization }
        let client = Self(session: AppleMusicSession(developer: developer, user: user, storefront: ""))
        let region = try await client.storefront()
        _ = try await client.request("/v1/me/library/songs", query: [URLQueryItem(name: "limit", value: "1")])
        return AppleMusicSession(developer: developer, user: user, storefront: region)
    }

    func storefront() async throws -> String {
        let data = try await request("/v1/me/storefront")
        let response = try JSONDecoder().decode(Collection.self, from: data)
        guard let region = response.data.first?.id, region.range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil
        else { throw Failure.authorization }
        return region
    }

    func match(_ track: NetEaseTrack) async throws -> Candidate? {
        let title = Self.key(track.title)
        let artist = Self.key(track.artist)
        let album = Self.albumKey(track.album)
        let credits = (track.artists ?? [track.artist]).map(Self.key)
        let sourceTitle = Self.titleCredit(track.title)
        guard !title.isEmpty, !artist.isEmpty, !album.isEmpty, track.duration > 0 else { return nil }
        let data = try await request("/v1/catalog/\(session.storefront)/search", query: [
            URLQueryItem(name: "term", value: "\(sourceTitle.title) \(track.artists?.first ?? track.artist)"),
            URLQueryItem(name: "types", value: "songs"),
            URLQueryItem(name: "limit", value: "20"),
        ])
        let response = try JSONDecoder().decode(Search.self, from: data)
        let matches = (response.results["songs"]?.data ?? []).filter {
            guard let fields = $0.attributes, let milliseconds = fields.durationInMillis else { return false }
            let candidateTitle = Self.titleCredit(fields.name ?? "")
            let candidateArtist = Self.key(fields.artistName ?? "")
            guard Self.albumKey(fields.albumName ?? "") == album,
                  abs(Double(milliseconds) / 1_000 - track.duration) <= 2.5 else { return false }
            if Self.key(fields.name ?? "") == title && candidateArtist == artist { return true }
            // A featured artist can move from the artist list into the title across catalogs.
            let guests = Set(candidateTitle.guests)
            return Self.key(candidateTitle.title) == Self.key(sourceTitle.title)
                && candidateArtist == credits.first && !guests.isEmpty
                && guests.isSubset(of: Set(credits.dropFirst()).union(sourceTitle.guests))
        }
        guard let first = matches.first else { return nil }
        if matches.count > 1 {
            guard let isrc = first.attributes?.isrc, !isrc.isEmpty,
                  matches.allSatisfy({ $0.attributes?.isrc == isrc }) else { return nil }
        }
        return Candidate(sourceID: track.id, catalogID: first.id)
    }

    func confirmed(_ ids: [String]) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let data = try await request("/v1/catalog/\(session.storefront)/songs", query: [
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "relate", value: "library"),
        ])
        let response = try JSONDecoder().decode(Collection.self, from: data)
        return Set(response.data.filter { $0.relationships?["library"]?.data.isEmpty == false }.map(\.id))
    }

    func add(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await request("/v1/me/library", method: "POST", query: [
            URLQueryItem(name: "ids[songs]", value: ids.joined(separator: ",")),
        ])
    }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = []) async throws -> Data {
        var endpoint = URLComponents()
        endpoint.scheme = "https"
        endpoint.host = "api.music.apple.com"
        endpoint.path = path
        if !query.isEmpty { endpoint.queryItems = query }
        guard let url = endpoint.url else { throw Failure.response(0) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(session.developer)", forHTTPHeaderField: "Authorization")
        request.setValue(session.user, forHTTPHeaderField: "Music-User-Token")
        request.setValue(session.user, forHTTPHeaderField: "Media-User-Token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.response(0) }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw Failure.authorization
        case 429: throw Failure.busy
        default: throw Failure.response(response.statusCode)
        }
    }

    private static func titleCredit(_ text: String) -> (title: String, guests: [String]) {
        let pattern = #"\s*[\[(](?:feat\.?|ft\.?)\s+([^\])]+)[\])]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let suffix = Range(match.range, in: text), let guests = Range(match.range(at: 1), in: text)
        else { return (text, []) }
        let names = text[guests].components(separatedBy: CharacterSet(charactersIn: ",、&＆"))
        return (String(text[..<suffix.lowerBound]), names.map(key).filter { !$0.isEmpty })
    }

    private static func albumKey(_ text: String) -> String {
        key(text.replacingOccurrences(of: #"\s*[-–]\s*(single|ep)$"#, with: "", options: [.regularExpression, .caseInsensitive]))
    }

    private static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
