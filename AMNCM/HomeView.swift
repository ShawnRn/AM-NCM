import SwiftUI

struct HomeView: View {
    let model: SyncModel
    @Environment(\.openWindow) private var openWindow
    @State private var showAppleLogin = false

    private var appleMusicDetail: String {
        let library = model.musicCount.map { "\($0.formatted()) 首歌曲" } ?? "等待读取本机资料库"
        if model.appleConnected { return library }
        let login = model.appleNeedsLogin ? "双向同步需要重新登录" : "登录后可开启双向同步"
        return "\(library) · \(login)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderView()

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ConnectionRow(title: "Apple Music", symbol: "music.note", tint: .pink,
                                      detail: appleMusicDetail, connected: model.appleConnected)
                        if !model.appleConnected {
                            Button(model.appleNeedsLogin ? "重新登录 Apple Music" : "登录 Apple Music") {
                                showAppleLogin = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.operation != nil)
                        }
                    }
                    Divider()
                    ConnectionRow(title: "网易云音乐", symbol: "heart.fill", tint: .red,
                                  detail: model.accountName ?? "同步到「我喜欢的音乐」",
                                  connected: model.accountID != nil)
                }

                if let update = model.updates.update {
                    Link(destination: update.url) {
                        Label("AM-NCM \(update.version) 可用 · 查看发布页", systemImage: "arrow.up.circle")
                    }
                }
                Divider()
                HomeActionView(model: model)

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let lastSync = model.lastSync {
                    LabeledContent("上次同步") {
                        Text(ChineseInterfaceText.format(lastSync.formatted(.dateTime.month().day().hour().minute())))
                        if let added = model.lastAdded {
                            Text(added > 0 ? "新增 \(added) 首红心" : "无需新增红心")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                if model.interval != .manual, let nextSync = model.nextSync {
                    LabeledContent("下次自动同步") {
                        Text(ChineseInterfaceText.format(nextSync.formatted(.dateTime.month().day().hour().minute())))
                    }
                    .font(.callout)
                }

                if !model.activities.isEmpty {
                    ActivityView(activities: model.activities)
                }
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            Button("匹配明细", systemImage: "list.bullet.rectangle") { openWindow(id: "report") }
                .disabled(!model.hasReport)
            SettingsLink()
        }
        .sheet(isPresented: $showAppleLogin) {
            AppleMusicLoginView(connected: model.connectAppleMusic)
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("把 Apple Music 带到网易云")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("同步到「我喜欢的音乐」，最近加入 Apple Music 资料库的歌曲排在最前。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConnectionRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let detail: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(activities) { activity in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(ChineseInterfaceText.format(activity.date.formatted(.dateTime.hour().minute().second())))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(ChineseInterfaceText.format(activity.text))
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 10)
        }
    }
}
