import SwiftUI

struct SyncSettingsView: View {
    let model: SyncModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmLogout = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Form {
            Section("同步") {
                Picker("同步周期", selection: Binding(get: { model.interval }, set: model.setInterval)) {
                    ForEach(SyncModel.Interval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .disabled(!model.ready || model.operation != nil)
                if model.interval == .manual {
                    Text("手动同步会先展示预览，再由你确认。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("App 运行时会自动添加匹配歌曲并更新顺序。Mac 睡眠期间错过的同步会在唤醒后补跑。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("启动") {
                Toggle("登录 Mac 时打开 AM-NCM", isOn: Binding(
                    get: { model.loginItem == .enabled || model.loginItem == .requiresApproval },
                    set: model.setLaunchAtLogin
                ))
                if model.loginItem == .requiresApproval {
                    Button("打开系统登录项设置", action: model.openLoginItemSettings)
                }
            }

            Section("账号") {
                LabeledContent("网易云音乐", value: model.accountName ?? "未登录")
                Button(model.accountID == nil ? "扫码登录" : "重新扫码登录") {
                    openWindow(id: "main")
                    model.login()
                }
                .disabled(model.operation != nil)
                if model.accountID != nil {
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                        .disabled(model.operation != nil)
                }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog("退出网易云音乐？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive, action: model.logout)
        } message: {
            Text("退出后会暂停自动同步。再次同步时需要扫码。")
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear(perform: model.refreshLoginItem)
        .onChange(of: activeState) { _, _ in model.refreshLoginItem() }
    }
}
