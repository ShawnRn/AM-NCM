import SwiftUI

struct HomeActionView: View {
    let model: SyncModel

    var body: some View {
        if let operation = model.operation {
            VStack(alignment: .leading, spacing: 14) {
                if operation == .login, let data = model.qrImage, let image = NSImage(data: data) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("打开手机上的网易云音乐，用「扫一扫」登录。")
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 184, height: 184)
                            .accessibilityLabel("网易云登录二维码")
                    }
                }

                if let fraction = model.fraction {
                    ProgressView(value: fraction) {
                        Text(model.stage)
                    } currentValueLabel: {
                        Text(model.counter ?? "")
                            .monospacedDigit()
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.stage)
                    }
                }

                if model.canCancel {
                    Button("取消", action: model.cancel)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                }
            }
        } else if let preview = model.preview {
            PreviewView(preview: preview, confirm: model.applyPreview, cancel: model.dismissPreview)
        } else if model.musicCount == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("第一步 · 连接 Apple Music")
                    .font(.headline)
                Text("请在 Mac 的音乐 App 中登录并打开资料库。出现系统提示时，选择「允许」。")
                    .foregroundStyle(.secondary)
                Button("连接 Apple Music", systemImage: "music.note", action: model.connectMusic)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        } else if model.accountID == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("第二步 · 登录网易云音乐")
                    .font(.headline)
                Text("用手机扫码并确认，即可连接「我喜欢的音乐」。")
                    .foregroundStyle(.secondary)
                Button("扫码登录", systemImage: "qrcode", action: model.login)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.lastSync == nil ? "准备好同步了" : "可以再次同步")
                    .font(.headline)
                Text("先看看将新增哪些歌曲。网易云已有的红心都会保留。")
                    .foregroundStyle(.secondary)
                Button("预览同步", systemImage: "arrow.trianglehead.clockwise", action: model.prepareSync)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        }
    }
}

private struct PreviewView: View {
    let preview: SyncModel.Preview
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("确认同步")
                .font(.headline)
            Text("资料库有 \(preview.count.formatted()) 首歌，已匹配 \(preview.matched.formatted()) 首，将新增 \(preview.additions.formatted()) 首红心。")
            if preview.review > 0 {
                Text("\(preview.review.formatted()) 首暂时跳过，可在「匹配明细」查看原因。")
                    .foregroundStyle(.secondary)
            }
            if preview.reverseCount > 0 {
                Text("将向 Apple Music 添加 \(preview.reverseCount.formatted()) 首歌曲。")
            }
            if preview.reverseReview > 0 {
                Text("有 \(preview.reverseReview.formatted()) 首新红心暂未找到可靠匹配。")
                    .foregroundStyle(.secondary)
            }
            if preview.reversePaused {
                Text("Apple Music 反向同步已暂停，请在设置中重新登录。")
                    .foregroundStyle(.secondary)
            }
            Text("已匹配歌曲按添加时间排列，网易云原有红心会保留。")
                .foregroundStyle(.secondary)
            HStack {
                Button("开始同步", systemImage: "arrow.trianglehead.clockwise", action: confirm)
                    .buttonStyle(.borderedProminent)
                Button("稍后再说", action: cancel)
                    .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }
}
