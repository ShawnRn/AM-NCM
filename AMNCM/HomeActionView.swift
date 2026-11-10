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
        } else if model.musicCount == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("第一步 · 读取 Apple Music 资料库")
                    .font(.headline)
                Text("请在 Mac 的音乐 App 中登录并打开资料库。出现系统提示时，选择「允许」。")
                    .foregroundStyle(.secondary)
                Button("读取资料库", systemImage: "music.note", action: model.connectMusic)
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
        }
    }
}
