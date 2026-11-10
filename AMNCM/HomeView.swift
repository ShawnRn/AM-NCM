import SwiftUI

struct HomeView: View {
    static let windowWidth: CGFloat = 570
    static let defaultContentHeight: CGFloat = 367
    private static let contentInset: CGFloat = 24
    let model: SyncModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAppleLogin = false
    @State private var contentHeight: CGFloat = 0
    @State private var currentDate = Date.now

    private enum Sheet: Identifiable {
        case appleLogin, settings, confirmation(SyncModel.Preview)

        var id: String {
            switch self {
            case .appleLogin: "appleLogin"
            case .settings: "settings"
            case .confirmation(let preview): preview.id.uuidString
            }
        }
    }

    private var presentedSheet: Sheet? {
        if showAppleLogin { return .appleLogin }
        if model.showsSettings { return .settings }
        return model.preview.map(Sheet.confirmation)
    }

    private var appleMusicDetail: String {
        let library = model.musicCount.map { "\($0.formatted()) 首歌曲" } ?? "等待读取本机资料库"
        if model.appleConnected { return library }
        let login = model.appleNeedsLogin ? "双向同步需要重新登录" : "登录后可开启双向同步"
        return "\(library) · \(login)"
    }

    private var syncTitle: String {
        let time = model.lastSync.map(formattedSyncDate) ?? "尚未同步"
        return "上次同步：\(time)"
    }

    private var appleMusicSummary: String {
        if let added = model.lastAppleAdded {
            return added > 0 ? "上次新增 \(added.formatted()) 首歌曲" : "上次无需新增歌曲"
        }
        return model.reverseEnabled ? "接收网易云新增红心" : "歌曲同步到网易云"
    }

    private var netEaseSummary: String {
        guard let added = model.lastAdded else { return "同步到「我喜欢的音乐」" }
        if model.lastReordered {
            return added > 0 ? "上次新增 \(added.formatted()) 首红心并调整顺序" : "上次已调整顺序"
        }
        return added > 0 ? "上次新增 \(added.formatted()) 首红心" : "上次无需更新"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(syncTitle)
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ConnectionRow(title: "Apple Music", symbol: "music.note", tint: .pink,
                                      detail: appleMusicDetail, summary: appleMusicSummary,
                                      connected: model.appleConnected)
                        if !model.appleConnected {
                            Button(model.appleNeedsLogin ? "重新登录 Apple Music" : "登录 Apple Music") {
                                showAppleLogin = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.operation != nil)
                        }
                    }
                    .padding(12)
                    Divider()
                        .padding(.leading, 50)
                        .padding(.trailing, 12)
                    ConnectionRow(title: "网易云音乐", symbol: "heart.fill", tint: .red,
                                  detail: model.accountName ?? "未登录", summary: netEaseSummary,
                                  connected: model.accountID != nil)
                        .padding(12)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                if let update = model.updates.update {
                    Link(destination: update.url) {
                        Label("AM-NCM \(update.version) 可用 · 查看发布页", systemImage: "arrow.up.circle")
                    }
                }
                HomeActionView(model: model)

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if !model.activities.isEmpty {
                    ActivityView(activities: model.activities)
                }

                if model.ready {
                    Spacer(minLength: 0)
                    syncFooter
                }
            }
            .frame(minHeight: Self.defaultContentHeight - Self.contentInset * 2, alignment: .topLeading)
            .padding(Self.contentInset)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { proxy in
                ceil(proxy.size.height)
            } action: { height in
                contentHeight = height
            }
        }
        .background(HomeWindowSizing(height: contentHeight, animate: !reduceMotion))
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            currentDate = .now
        }
        .toolbar {
            Button("匹配明细", systemImage: "list.bullet.rectangle") { openWindow(id: "report") }
                .disabled(!model.hasReport)
            Button("设置…", systemImage: "gear", action: model.showSettings)
        }
        .sheet(item: Binding(get: { presentedSheet }, set: { _ in dismissSheet() })) { sheet in
            switch sheet {
            case .appleLogin:
                AppleMusicLoginView(connected: model.connectAppleMusic)
            case .settings:
                SyncSettingsView(model: model)
            case .confirmation(let preview):
                SyncConfirmationView(preview: preview, reverseEnabled: model.reverseEnabled,
                                     confirm: model.applyPreview, cancel: model.dismissPreview)
            }
        }
    }

    private var syncFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let preview = model.inlinePreview {
                    HStack(spacing: 8) {
                        Text(preview.updatesOrder ? "无需新增，仅网易云顺序待调整" : "本次无需新增或调整顺序")
                        if preview.updatesOrder {
                            Button("调整顺序", action: model.applyPreview)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    if preview.reversePaused {
                        Text("Apple Music 同步已暂停，请重新登录。")
                    }
                } else if model.interval != .manual, let nextSync = model.nextSync {
                    Text("下次自动同步 \(formattedSyncDate(nextSync))")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            Button("手动同步", systemImage: "arrow.trianglehead.clockwise", action: model.prepareSync)
                .disabled(model.operation != nil || model.preview != nil)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
    }

    private func formattedSyncDate(_ date: Date) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        let style = Calendar.current.isDate(date, inSameDayAs: currentDate) ? time : time.month().day()
        return ChineseInterfaceText.format(date.formatted(style))
    }

    private func dismissSheet() {
        switch presentedSheet {
        case .appleLogin: showAppleLogin = false
        case .settings: model.showsSettings = false
        case .confirmation: model.dismissPreview()
        case nil: break
        }
    }
}

private struct ConnectionRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let detail: String
    let summary: String
    let connected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                Text(summary)
                    .font(.callout)
                    .padding(.top, 3)
            }
            Spacer()
            if connected {
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct ActivityView: View {
    let activities: [SyncModel.Activity]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("活动记录", isExpanded: $expanded) {
            ViewThatFits(in: .vertical) {
                activityRows
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView { activityRows }
                    .defaultScrollAnchor(.top)
            }
            .frame(maxHeight: 200)
            .padding(.top, 8)
        }
    }

    private var activityRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(activities) { activity in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ChineseInterfaceText.format(activity.date.formatted(.dateTime.hour().minute().second())))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(ChineseInterfaceText.format(activity.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeWindowSizing: NSViewRepresentable {
    let height: CGFloat
    let animate: Bool

    func makeNSView(context: Context) -> SizingView { SizingView() }

    func updateNSView(_ view: SizingView, context: Context) {
        view.update(height: height, animate: animate)
    }

    final class SizingView: NSView {
        private var height: CGFloat = 0
        private var animate = false
        private var needsResize = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        func update(height: CGFloat, animate: Bool) {
            self.animate = animate
            guard height != self.height else { return }
            self.height = height
            scheduleResize()
        }

        private func scheduleResize() {
            guard !needsResize else { return }
            needsResize = true
            // Apply after SwiftUI has finished laying out the scroll content.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                needsResize = false
                guard height > 0, let window, !window.inLiveResize,
                      !window.styleMask.contains(.fullScreen),
                      let screen = window.screen else { return }
                window.styleMask.remove(.resizable)
                let oldFrame = window.frame
                let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).height
                let desired = height + oldFrame.height - window.contentLayoutRect.height
                let top = min(screen.visibleFrame.maxY, max(oldFrame.maxY, screen.visibleFrame.minY + minimum))
                let adjusted = min(max(desired, minimum), top - screen.visibleFrame.minY)
                let width = HomeView.windowWidth
                guard abs(oldFrame.height - adjusted) >= 1 || abs(oldFrame.width - width) >= 1 else { return }
                window.setFrame(NSRect(x: oldFrame.minX, y: top - adjusted, width: width, height: adjusted),
                                display: true, animate: animate && window.isVisible)
            }
        }
    }
}
