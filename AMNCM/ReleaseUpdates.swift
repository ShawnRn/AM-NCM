import Foundation
import Observation

@MainActor @Observable
final class ReleaseUpdates {
    struct Update {
        let version: String
        let url: URL
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    nonisolated static let releasesURL = URL(string: "https://github.com/ShawnRn/AM-NCM/releases")!
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    private(set) var update: Update?
    private(set) var checking = false
    private(set) var status: String?

    func checkIfDue() async {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
        if let last, Date.now.timeIntervalSince(last) < 86_400 { return }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard !checking else { return }
        checking = true
        status = nil
        defer { checking = false }
        if !manual { UserDefaults.standard.set(Date.now, forKey: "lastUpdateCheck") }
        do {
            let release = try await Self.latestRelease()
            let tag = release.tag_name
            let latest = String(tag.hasPrefix("v") ? tag.dropFirst() : tag[...])
            guard latest.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
                  !release.draft, !release.prerelease else { throw CheckFailure.unavailable }
            if latest.compare(version, options: .numeric) == .orderedDescending {
                update = Update(version: latest, url: Self.releasesURL.appending(path: "tag").appending(path: tag))
            } else {
                update = nil
                if manual { status = "当前已是最新版本。" }
            }
            UserDefaults.standard.set(Date.now, forKey: "lastUpdateCheck")
        } catch {
            if manual { status = "暂时无法检查更新，可打开 GitHub 发布页查看。" }
        }
    }

    private enum CheckFailure: Error { case unavailable }

    private static func latestRelease() async throws -> Release {
        let endpoint = "repos/ShawnRn/AM-NCM/releases/latest"
        guard let url = URL(string: "https://api.github.com/\(endpoint)") else { throw CheckFailure.unavailable }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CheckFailure.unavailable }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
