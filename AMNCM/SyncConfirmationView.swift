import SwiftUI

struct SyncConfirmationView: View {
    let preview: SyncModel.Preview
    let reverseEnabled: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.openWindow) private var openWindow

    private var netEaseChange: String {
        preview.additions == 0 ? "无需新增红心" : "新增 \(preview.additions.formatted()) 首红心"
    }

    private var appleMusicChange: String {
        if preview.reversePaused { return "同步已暂停" }
        if preview.reverseCount == 0 { return "无需新增歌曲" }
        return "预计新增 \(preview.reverseCount.formatted()) 首"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("确认同步")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("已匹配 \(preview.matched.formatted()) 首 Apple Music 歌曲，共 \(preview.count.formatted()) 首")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    platform("Apple Music", symbol: "music.note", tint: .pink)
                    VStack(spacing: 10) {
                        direction(netEaseChange, destination: "网易云音乐", pointsRight: true,
                                  hasChanges: preview.additions > 0)
                        if reverseEnabled {
                            direction(appleMusicChange, destination: "Apple Music", pointsRight: false,
                                      hasChanges: preview.reverseCount > 0 && !preview.reversePaused)
                        }
                    }
                    platform("网易云音乐", symbol: "heart.fill", tint: .red)
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                summary
            }
            .padding(24)

            Divider()
            HStack(spacing: 8) {
                Button("查看匹配明细", systemImage: "list.bullet.rectangle") {
                    openWindow(id: "report")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("稍后再说", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("开始同步", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 510)
        .onAppear {
            if !NSApplication.shared.isActive {
                NSApplication.shared.requestUserAttention(.informationalRequest)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.updatesOrder ? "网易云将调整顺序" : "网易云顺序无需调整")
                        .fontWeight(.semibold)
                    if preview.updatesOrder {
                        Text("匹配歌曲按 Apple Music 的添加时间排列，原有红心会保留。")
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
            }
            if preview.reversePaused {
                Text("重新登录 Apple Music 后可恢复从网易云同步。")
                    .foregroundStyle(.secondary)
            } else if preview.reverseCount > 0 {
                Text("Apple Music 只添加资料库中没有的歌曲。")
                    .foregroundStyle(.secondary)
            }
            if preview.review > 0 {
                Text("\(preview.review.formatted()) 首 Apple Music 歌曲暂时跳过。")
                    .foregroundStyle(.secondary)
            }
            if preview.reverseReview > 0 {
                Text("\(preview.reverseReview.formatted()) 首网易云新红心暂未匹配到 Apple Music。")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func platform(_ title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.semibold))
        }
        .frame(width: 88)
    }

    private func direction(_ label: String, destination: String, pointsRight: Bool, hasChanges: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.callout.weight(hasChanges ? .semibold : .regular))
                .foregroundStyle(hasChanges ? Color.primary : Color.secondary)
                .accessibilityLabel("\(destination)\(destination == "Apple Music" ? " " : "")\(label)")
            HStack(spacing: -1) {
                if !pointsRight { Image(systemName: "chevron.left") }
                Capsule().frame(height: hasChanges ? 2 : 1)
                if pointsRight { Image(systemName: "chevron.right") }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(hasChanges ? Color.accentColor : Color.secondary.opacity(0.5))
            .accessibilityHidden(true)
        }
    }
}
