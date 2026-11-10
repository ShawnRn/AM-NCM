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
        case checking, connecting, enablingReverse, login, preview, sync
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
        var reverseCount = 0
        var reverseReview = 0
        var reversePaused = false
    }

    let notifications = SyncNotifications()
    let updates = ReleaseUpdates()

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
    private(set) var reverseEnabled = false
    private var appleSession = AppleMusicSession.load()
    private(set) var appleNeedsLogin = false
    var appleConnected: Bool { appleSession != nil && !appleNeedsLogin }
    private var reverseMatches: [AppleMusicImport.Candidate] = []
    private var reverseAlreadyInLibrary: Set<String> = []
    private var plannedLikes: [String] = []
    private(set) var hasReport = false
    private(set) var reportVersion = 0
    var error: String?

    var ready: Bool { musicCount != nil && accountID != nil }
    var canCancel: Bool { operation == .login || operation == .preview || operation == .enablingReverse }
    var reverseSwitchOn: Bool { reverseEnabled || operation == .enablingReverse }

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

    func setReverseEnabled(_ enabled: Bool) {
        if !enabled, operation == .enablingReverse {
            cancel()
            return
        }
        guard let accountID, operation == nil, preview == nil else { return }
        if !enabled {
            defaults.removeObject(forKey: reverseKey(accountID))
            reverseEnabled = false
            log("已关闭双向同步")
            return
        }
        guard appleConnected else {
            error = "请先连接 Apple Music，再开启双向同步。"
            return
        }
        startOperation(.enablingReverse, "正在记录当前网易云红心") {
            let likes = try await self.currentLikes(accountID: accountID)
            try Task.checkCancellation()
            self.saveSeen(Set(likes), accountID: accountID)
            self.reverseEnabled = true
            self.log("已开启双向同步，将从下一首新增红心开始")
        }
    }

    func connectAppleMusic(_ session: AppleMusicSession) throws {
        try session.save()
        appleSession = session
        appleNeedsLogin = false
        preview = nil
        error = nil
        log("已连接 Apple Music")
    }

    func disconnectAppleMusic() {
        guard operation == nil else { return }
        do {
            try AppleMusicSession.disconnect()
            appleSession = nil
            appleNeedsLogin = false
            preview = nil
            log("已断开 Apple Music 网页登录")
        } catch {
            self.error = ChineseInterfaceText.format(error.localizedDescription)
        }
    }

    private func reverseKey(_ accountID: String) -> String {
        "reverseSeen.\(accountID)"
    }

    private func seenLikes(accountID: String) -> Set<String> {
        Set(defaults.stringArray(forKey: reverseKey(accountID)) ?? [])
    }

    private func saveSeen(_ ids: Set<String>, accountID: String) {
        defaults.set(ids.sorted(), forKey: reverseKey(accountID))
    }

    private func currentLikes(accountID: String) async throws -> [String] {
        var likes: [String]?
        try await engine.run("likes", account: accountID) { event in
            if event.kind == "likes" { likes = event.ids }
        }
        guard let likes else { throw Engine.Failure("暂时无法读取网易云红心，请重试。") }
        return likes
    }

    func prepareSync() {
        guard ready, let accountID else { return }
        startOperation(.preview, "正在准备同步预览") {
            try await self.buildPreview(accountID: accountID)
        }
    }

    func applyPreview() {
        guard preview != nil, let accountID else { return }
        startOperation(.sync, "正在同步到「我喜欢的音乐」") {
            try await self.apply(accountID: accountID)
        }
    }

    func dismissPreview() { preview = nil }

    func cancel() {
        guard canCancel else { return }
        operationTask?.cancel()
        engine.cancel()
    }

    func setInterval(_ value: Interval) {
        interval = value
        defaults.set(value.rawValue, forKey: "interval")
        updateNextSync(value == .manual ? nil : .now.addingTimeInterval(Double(value.rawValue)))
        log(value == .manual ? "已关闭自动同步" : "自动同步已设为「\(value.title)」")
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
            self.error = "无法更改登录启动设置。\(ChineseInterfaceText.format(error.localizedDescription))"
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
            try await self.apply(accountID: accountID)
        }
    }

    private func buildPreview(accountID: String) async throws {
        preview = nil
        reverseMatches = []
        reverseAlreadyInLibrary = []
        plannedLikes = []
        setProgress("正在读取 Apple Music 资料库")
        try await run("scan")
        setProgress("正在检查网易云曲目")
        try await run("plan", account: accountID)
        guard var result = preview else {
            throw Engine.Failure("这次匹配还没完成。已保存进度，可以稍后继续。")
        }
        if reverseEnabled {
            preview = nil
            let seen = seenLikes(accountID: accountID)
            let newLikes = plannedLikes.filter { !seen.contains($0) }
            if !newLikes.isEmpty {
                let report = try await SyncReport.load()
                let linked = Set(report.entries.compactMap(\.targetID))
                reverseAlreadyInLibrary = Set(newLikes).intersection(linked)
                let pending = newLikes.filter { !linked.contains($0) }
                if !pending.isEmpty {
                    setProgress("正在读取新增红心")
                    var tracks: [NetEaseTrack] = []
                    try await engine.run("details", account: accountID, ids: pending) { event in
                        if event.kind == "details" { tracks = event.tracks ?? [] }
                    }
                    if let session = appleSession, appleConnected {
                        let client = AppleMusicImport(session: session)
                        var lastSearch: ContinuousClock.Instant?
                        do {
                            for (index, track) in tracks.enumerated() {
                                try Task.checkCancellation()
                                if let lastSearch {
                                    try await ContinuousClock().sleep(until: lastSearch + .milliseconds(500))
                                }
                                lastSearch = .now
                                setProgress("正在匹配 Apple Music", completed: index + 1, total: tracks.count)
                                if let candidate = try await client.match(track) { reverseMatches.append(candidate) }
                            }
                            result.reverseCount = Set(reverseMatches.map(\.catalogID)).count
                            result.reverseReview = pending.count - reverseMatches.count
                        } catch AppleMusicImport.Failure.authorization {
                            appleNeedsLogin = true
                            reverseMatches = []
                            result.reversePaused = true
                            log("Apple Music 授权已失效，请在设置中重新登录")
                        }
                    } else {
                        result.reversePaused = true
                    }
                }
            }
        }
        try Task.checkCancellation()
        preview = result
    }

    private func apply(accountID: String) async throws {
        let reversePaused = preview?.reversePaused == true
        preview = nil
        try await run("apply", account: accountID)
        guard reverseEnabled else {
            markSyncComplete()
            return
        }
        if reversePaused { throw AppleMusicImport.Failure.authorization }
        let current = Set(try await currentLikes(accountID: accountID))
        var seen = seenLikes(accountID: accountID).intersection(current)
        seen.formUnion(reverseAlreadyInLibrary.intersection(current))
        saveSeen(seen, accountID: accountID)
        if let session = appleSession, appleConnected {
            let client = AppleMusicImport(session: session)
            let matches = reverseMatches.filter { current.contains($0.sourceID) }
            let catalogIDs = Array(Set(matches.map(\.catalogID))).sorted()
            var verified: Set<String> = []
            do {
                for offset in stride(from: 0, to: catalogIDs.count, by: 25) {
                    let batch = Array(catalogIDs.dropFirst(offset).prefix(25))
                    setProgress("正在同步到 Apple Music", completed: verified.count, total: catalogIDs.count)
                    var confirmed = try await client.confirmed(batch)
                    let missing = batch.filter { !confirmed.contains($0) }
                    if !missing.isEmpty {
                        try await client.add(missing)
                        setProgress("正在核对 Apple Music 资料库")
                        for attempt in 0..<4 {
                            if attempt > 0 { try await Task.sleep(for: .seconds(2)) }
                            confirmed.formUnion(try await client.confirmed(missing))
                            if missing.allSatisfy(confirmed.contains) { break }
                        }
                    }
                    verified.formUnion(confirmed)
                    seen.formUnion(matches.filter { confirmed.contains($0.catalogID) }.map(\.sourceID))
                    saveSeen(seen, accountID: accountID)
                }
            } catch AppleMusicImport.Failure.authorization {
                appleNeedsLogin = true
                log("Apple Music 授权已失效，请在设置中重新登录")
                throw AppleMusicImport.Failure.authorization
            }
            if !verified.isEmpty { log("已核对 Apple Music 资料库中的 \(verified.count) 首歌曲") }
            if verified.count < catalogIDs.count {
                throw Engine.Failure("Apple Music 尚未显示全部歌曲，下次同步会再次核对。")
            }
        }
        markSyncComplete()
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
                log(operation == .enablingReverse ? "已取消开启双向同步" : "已取消。已完成的匹配进度会保留。")
            } catch {
                guard !quietly else { return }
                self.error = ChineseInterfaceText.format(error.localizedDescription)
                log("任务暂停：\(ChineseInterfaceText.format(error.localizedDescription))")
                if operation == .sync || operation == .preview {
                    let body = (error as? AppleMusicImport.Failure) == .authorization
                        ? "请打开 AM-NCM，重新登录 Apple Music。"
                        : "打开 AM-NCM 查看详情。"
                    notifications.deliver(.failure, title: operation == .sync ? "同步未完成" : "同步预览失败", body: body)
                }
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
            reverseEnabled = false
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
                reverseEnabled = defaults.object(forKey: reverseKey(uid)) != nil
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
            plannedLikes = event.ids ?? []
            hasReport = true
            reportVersion += 1
            if event.incomplete == 0, event.uid == accountID {
                preview = Preview(count: event.count ?? 0, matched: event.matched ?? 0,
                                  additions: event.additions ?? 0, review: event.review ?? 0)
                log("同步预览已准备好")
            }
        case "done":
            if reverseEnabled, let accountID {
                saveSeen(seenLikes(accountID: accountID).union(event.ids ?? []), accountID: accountID)
            }
            reportVersion += 1
            lastAdded = event.additions
            defaults.set(lastAdded, forKey: "lastAdded")
            log("已核对网易云 \(event.count ?? 0) 首歌曲的顺序")
        default:
            break
        }
    }

    private func markSyncComplete() {
        lastSync = .now
        defaults.set(lastSync, forKey: "lastSync")
        if interval != .manual { updateNextSync(.now.addingTimeInterval(Double(interval.rawValue))) }
        log("同步完成")
        notifications.deliver(.success, title: "同步完成", body: "已核对本次同步结果。")
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
