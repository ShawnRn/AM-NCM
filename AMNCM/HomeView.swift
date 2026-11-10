import SwiftUI

struct HomeView: View {
    let model: SyncModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderView()

                VStack(spacing: 14) {
                    ConnectionRow(title: "Apple Music", symbol: "music.note", tint: .pink,
                                  detail: model.musicCount.map { "\($0.formatted()) 首歌曲" } ?? "读取 Mac 上的音乐资料库",
                                  connected: model.musicCount != nil)
                    Divider()
                    ConnectionRow(title: "网易云音乐", symbol: "heart.fill", tint: .red,
                                  detail: model.accountName ?? "同步到「我喜欢的音乐」",
                                  connected: model.accountID != nil)
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
                        Text(lastSync, format: .dateTime.month().day().hour().minute())
                        if let added = model.lastAdded {
                            Text(added > 0 ? "新增 \(added) 首红心" : "无需新增红心")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                if model.interval != .manual, let nextSync = model.nextSync {
                    LabeledContent("下次自动同步") {
                        Text(nextSync, format: .dateTime.month().day().hour().minute())
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
                        Text(activity.date, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(activity.text)
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 10)
        }
    }
}
