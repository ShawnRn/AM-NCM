import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class SyncModel {
    enum Interval: Int, CaseIterable, Identifiable {
        case manual = 0
        case hourly = 3600
        case daily = 86400
        case weekly = 604800

        var id: Self { self }
        var title: String {
            switch self {
            case .manual: "仅手动"
            case .hourly: "每小时"
            case .daily: "每天"
            case .weekly: "每周"
            }
        }
    }

    enum Operation: Equatable {
        case checking, connecting, login, preview, sync
    }

    struct Activity: Identifiable, Codable {
        let id: UUID
        let date: Date
        let text: String

        init(text: String) {
            id = UUID()
            date = .now
            self.text = text
        }
    }

    struct Preview {
        let count: Int
        let matched: Int
        let additions: Int
        let review: Int
    }

    private let engine = Engine()
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var lastAccountCheck = Date.distantPast
    private(set) var musicCount: Int?
    private(set) var accountName: String?
    private(set) var accountID: String?
    private(set) var operation: Operation?
    private(set) var preview: Preview?
    private(set) var qrImage: Data?
    private(set) var qrScanned = false
    private(set) var stage = ""
    private(set) var fraction: Double?
    private(set) var counter: String?
    private(set) var activities: [Activity] = []
    private(set) var lastSync: Date?
    private(set) var nextSync: Date?
    private(set) var lastAdded: Int?
    private(set) var interval: Interval = .manual
    private(set) var loginItem: SMAppService.Status = .notRegistered
    private(set) var hasReport = false
    private(set) var reportVersion = 0
    var error: String?

    var ready: Bool { musicCount != nil && accountID != nil }
    var canCancel: Bool { operation == .login || operation == .preview }

    init() {
        musicCount = defaults.object(forKey: "musicCount") as? Int
        lastSync = defaults.object(forKey: "lastSync") as? Date
        lastAdded = defaults.object(forKey: "lastAdded") as? Int
        nextSync = defaults.object(forKey: "nextSync") as? Date
        interval = Interval(rawValue: defaults.integer(forKey: "interval")) ?? .manual
        loginItem = SMAppService.mainApp.status
        hasReport = FileManager.default.fileExists(atPath: SyncReport.location.path)
        if let data = defaults.data(forKey: "activityHistory"),
           let history = try? JSONDecoder().decode([Activity].self, from: data) {
            activities = Array(history.prefix(80))
        }
    }

    func start() {
        guard scheduler == nil else { return }
        checkAccount()
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                self?.runScheduledSyncIfDue()
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            }
        }
    }

    func stop() {
        scheduler?.cancel()
        engine.cancel()
    }

    func connectMusic() {
        startOperation(.connecting, "正在读取 Apple Music 资料库") {
            try await self.run("scan")
        }
    }

    func login() {
        startOperation(.login, "正在生成网易云登录二维码") {
            self.qrScanned = false
            try await self.run("login")
        }
    }

    func logout() {
        startOperation(.checking, "正在退出网易云音乐") {
            try await self.run("logout")
        }
    }

    func prepareSync() {
        guard ready, let accountID else { return }
        startOperation(.preview, "正在准备同步预览") {
            try await self.buildPreview(accountID: accountID)
        }
    }

    func applyPreview() {
        guard preview != nil, let accountID else { return }
        startOperation(.sync, "正在同步到我喜欢的音乐") {
            self.preview = nil
            try await self.run("apply", account: accountID)
        }
    }

    func dismissPreview() { preview = nil }

    func cancel() {
        guard canCancel else { return }
        engine.cancel()
    }

    func setInterval(_ value: Interval) {
        interval = value
        defaults.set(value.rawValue, forKey: "interval")
        updateNextSync(value == .manual ? nil : .now.addingTimeInterval(Double(value.rawValue)))
        log(value == .manual ? "已关闭自动同步" : "自动同步已设为\(value.title)")
    }

    func refreshLoginItem() { loginItem = SMAppService.mainApp.status }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItem()
            log(enabled ? "已请求在登录 Mac 时启动" : "已关闭登录时启动")
        } catch {
            refreshLoginItem()
            self.error = "无法更改登录启动设置。\(error.localizedDescription)"
        }
    }

    func openLoginItemSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func checkAccount() {
        lastAccountCheck = .now
        startOperation(.checking, "正在检查网易云登录状态", quietly: true) {
            try await self.run("account")
        }
    }

    private func runScheduledSyncIfDue() {
        guard operation == nil, preview == nil, interval != .manual,
              let nextSync, nextSync <= .now else { return }
        guard let accountID else {
            if Date.now.timeIntervalSince(lastAccountCheck) >= 300 { checkAccount() }
            return
        }
        guard ready else { return }
        startOperation(.sync, "已到自动同步时间") {
            // Persist a retry date before touching the remote account.
            self.updateNextSync(.now.addingTimeInterval(min(Double(self.interval.rawValue), 3600)))
            try await self.buildPreview(accountID: accountID)
            self.preview = nil
            try await self.run("apply", account: accountID)
        }
    }

    private func buildPreview(accountID: String) async throws {
        preview = nil
        setProgress("正在读取 Apple Music 资料库")
        try await run("scan")
        setProgress("正在检查网易云曲目")
        try await run("plan", account: accountID)
        guard preview != nil else {
            throw Engine.Failure("这次匹配还没完成。已保存进度，可以稍后继续。")
        }
    }

    private func run(_ action: String, account: String? = nil) async throws {
        try await engine.run(action, account: account, receive: handle)
    }

    private func startOperation(_ operation: Operation, _ text: String, quietly: Bool = false, work: @escaping @MainActor () async throws -> Void) {
        guard self.operation == nil else { return }
        error = nil
        self.operation = operation
        setProgress(text)
        operationTask = Task {
            defer {
                self.operation = nil
                qrImage = nil
                operationTask = nil
            }
            do {
                try await work()
            } catch is CancellationError {
                log("已取消。已完成的匹配进度会保留。")
            } catch {
                guard !quietly else { return }
                self.error = error.localizedDescription
                log("任务暂停：\(error.localizedDescription)")
            }
        }
    }

    private func handle(_ event: EngineEvent) {
        switch event.kind {
        case "progress":
            setProgress(event.text ?? "正在处理", completed: event.completed, total: event.total)
        case "waiting":
            if let text = event.text {
                log(text)
                stage = text
            }
        case "logout":
            accountID = nil
            accountName = nil
            preview = nil
            setInterval(.manual)
            log("已退出网易云音乐")
        case "message":
            if let text = event.text, !text.hasPrefix("原始曲目顺序已备份") { log(text) }
        case "qr":
            if let data = event.data {
                qrImage = Data(base64Encoded: data)
                setProgress("等待手机扫码")
            }
        case "scanned":
            if !qrScanned {
                qrScanned = true
                setProgress("请在手机上确认登录")
            }
        case "account":
            if let uid = event.uid {
                if accountID != nil && accountID != uid {
                    preview = nil
                    setInterval(.manual)
                }
                if let scheduledUID = defaults.string(forKey: "scheduledUID"), scheduledUID != uid {
                    setInterval(.manual)
                }
                accountID = uid
                accountName = event.name
                log("已连接网易云音乐")
            }
        case "library":
            if let count = event.count {
                musicCount = count
                defaults.set(count, forKey: "musicCount")
                log("已读取 \(count) 首 Apple Music 歌曲")
            }
        case "plan":
            hasReport = true
            reportVersion += 1
            if event.incomplete == 0, event.uid == accountID {
                preview = Preview(count: event.count ?? 0, matched: event.matched ?? 0,
                                  additions: event.additions ?? 0, review: event.review ?? 0)
                log("同步预览已准备好")
            }
        case "done":
            lastSync = .now
            reportVersion += 1
            lastAdded = event.additions
            defaults.set(lastSync, forKey: "lastSync")
            defaults.set(lastAdded, forKey: "lastAdded")
            if interval != .manual { updateNextSync(.now.addingTimeInterval(Double(interval.rawValue))) }
            log("同步完成，已核对 \(event.count ?? 0) 首歌曲的顺序")
        default:
            break
        }
    }

    private func updateNextSync(_ date: Date?) {
        nextSync = date
        defaults.set(date, forKey: "nextSync")
        defaults.set(date == nil ? nil : accountID, forKey: "scheduledUID")
    }

    private func setProgress(_ text: String, completed: Int? = nil, total: Int? = nil) {
        if stage != text || operation == nil { log(text) }
        stage = text
        if let completed, let total, total > 0 {
            fraction = Double(completed) / Double(total)
            counter = "\(completed.formatted()) / \(total.formatted()) 首"
        } else {
            fraction = nil
            counter = nil
        }
    }

    private func log(_ text: String) {
        activities.insert(Activity(text: text), at: 0)
        if activities.count > 80 { activities.removeLast() }
        defaults.set(try? JSONEncoder().encode(activities), forKey: "activityHistory")
    }
}
