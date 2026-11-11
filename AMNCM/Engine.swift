import Foundation

struct EngineEvent: Decodable {
    let kind: String
    let text: String?
    let data: String?
    let name: String?
    let uid: String?
    let count: Int?
    let completed: Int?
    let total: Int?
    let matched: Int?
    let additions: Int?
    let review: Int?
    let incomplete: Int?
    let updatesOrder: Bool?
    let changed: Bool?
    let reordered: Bool?
    let ids: [String]?
    let currentIDs: [String]?
    let tracks: [NetEaseTrack]?
}

@MainActor
final class Engine {
    static let playlistRetryLimitKey = "playlistRetryLimit"
    static let defaultPlaylistRetryLimit = 3
    static let playlistRetryLimits = 0...10

    private var process: Process?
    private var cancelled = false

    func cancel() {
        cancelled = true
        if process?.isRunning == true { process?.terminate() }
    }

    func run(_ action: String, account: String? = nil, ids: [String] = [], receive: (EngineEvent) -> Void) async throws {
        guard process == nil else { throw Failure("已有任务正在运行。") }
        guard let resources = Bundle.main.resourceURL,
              let helpers = Bundle.main.url(forAuxiliaryExecutable: "node")
                ?? Bundle.main.bundleURL.appending(path: "Contents/Helpers/node").existingExecutable
        else { throw Failure("同步组件未安装，请重新安装 AM-NCM。") }

        let task = Process()
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let (chunks, continuation) = AsyncStream<Data>.makeStream()
        task.executableURL = helpers
        task.arguments = [resources.appending(path: "Engine/ncm.cjs").path, action] + ids
        var environment = ProcessInfo.processInfo.environment
        for key in ["NODE_OPTIONS", "NODE_PATH", "NETEASE_COOKIE", "AMNCM_EXPECTED_UID"] {
            environment.removeValue(forKey: key)
        }
        environment["AMNCM_EMBEDDED"] = "1"
        environment["AMNCM_EXPECTED_UID"] = account
        let retryLimit = UserDefaults.standard.object(forKey: Self.playlistRetryLimitKey) as? Int
            ?? Self.defaultPlaylistRetryLimit
        environment["AMNCM_PLAYLIST_RETRY_LIMIT"] = String(
            Self.playlistRetryLimits.contains(retryLimit) ? retryLimit : Self.defaultPlaylistRetryLimit
        )
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = pipe

        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        cancelled = false
        process = task
        defer {
            reader.readabilityHandler = nil
            continuation.finish()
            process = nil
        }
        try task.run()
        var pending = Data()
        var failure: String?
        for await data in chunks {
            pending.append(data)
            while let end = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: end)
                pending.removeSubrange(...end)
                guard let event = try? JSONDecoder().decode(EngineEvent.self, from: Data(line)) else { continue }
                if event.kind == "error" { failure = event.text }
                receive(event)
            }
        }
        let status = await Task.detached {
            task.waitUntilExit()
            return task.terminationStatus
        }.value
        if cancelled { throw CancellationError() }
        if status != 0 {
            throw Failure(failure ?? "任务意外停止，请重试。")
        }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

private extension URL {
    var existingExecutable: URL? {
        FileManager.default.isExecutableFile(atPath: path) ? self : nil
    }
}
