import SwiftUI

struct SyncSettingsView: View {
    let model: SyncModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var appleLogin: AppleLoginPurpose?
    @Environment(\.controlActiveState) private var activeState

    private enum AppleLoginPurpose: Identifiable {
        case account, enableReverse

        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("「AM-NCM」设置")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
            settingsForm
                .frame(height: 264)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480)
        .onAppear(perform: refreshSettings)
        .onChange(of: activeState) { _, state in
            if state == .key { refreshSettings() }
        }
    }

    private var settingsForm: some View {
        Form {
            Section("同步") {
                Toggle("双向同步", isOn: Binding(get: { model.reverseSwitchOn }, set: setReverseEnabled))
                    .disabled(!model.ready || (model.operation != nil && model.operation != .enablingReverse)
                              || model.preview != nil)
                if model.operation == .enablingReverse {
                    ProgressView("正在记录现有红心，完成后开始双向同步")
                        .controlSize(.small)
                }
                Text(reverseSyncDescription)
                    .foregroundStyle(.secondary)
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                Picker("同步周期", selection: Binding(get: { model.interval }, set: model.setInterval)) {
                    ForEach(SyncModel.Interval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .disabled(!model.ready || (model.operation != nil && model.operation != .enablingReverse))
                if model.interval == .manual {
                    Text("手动同步会先展示预览，再由你确认。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("App 运行时会自动同步。有变化时，才会发送已开启的成功通知。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("通知") {
                Toggle("同步成功", isOn: Binding(get: { model.notifications.success },
                                               set: { model.notifications.set(.success, enabled: $0) }))
                Toggle("同步失败", isOn: Binding(get: { model.notifications.failure },
                                               set: { model.notifications.set(.failure, enabled: $0) }))
                if model.notifications.requesting {
                    ProgressView("正在请求通知权限").controlSize(.small)
                }
                if let message = model.notifications.message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            .disabled(model.notifications.requesting)

            Section("更新") {
                LabeledContent("当前版本", value: model.updates.version)
                if let update = model.updates.update {
                    Link("查看新版 \(update.version)", destination: update.url)
                } else {
                    Button(model.updates.checking ? "正在检查更新…" : "检查更新") {
                        Task { await model.updates.check(manual: true) }
                    }
                    .disabled(model.updates.checking)
                }
                Link("查看 GitHub 发布页", destination: ReleaseUpdates.releasesURL)
                if let status = model.updates.status { Text(status).foregroundStyle(.secondary) }
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
                LabeledContent("Apple Music", value: model.appleConnected ? "已连接" : (model.appleNeedsLogin ? "需要重新登录" : "未登录"))
                Button(model.appleConnected ? "重新登录 Apple Music" : "登录 Apple Music") {
                    appleLogin = .account
                }
                .disabled(model.operation != nil)
                if model.appleConnected {
                    Button("断开 Apple Music", action: model.disconnectAppleMusic)
                        .disabled(model.operation != nil)
                }
                LabeledContent("网易云音乐", value: model.accountName ?? "未登录")
                Button(model.accountID == nil ? "扫码登录" : "重新扫码登录") {
                    dismiss()
                    model.login()
                }
                .disabled(model.operation != nil)
                if model.accountID != nil {
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                        .disabled(model.operation != nil)
                }
            }

            Section("关于「AM-NCM」") {
                Text("Made with ❤️ by Shawn Rain (feat. Codex)")
                Link("GitHub 项目主页", destination: ReleaseUpdates.releasesURL.deletingLastPathComponent())
            }
        }
        .confirmationDialog("退出网易云音乐？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive, action: model.logout)
        } message: {
            Text("退出后会暂停自动同步。再次同步时需要扫码。")
        }
        .sheet(item: $appleLogin) { purpose in
            AppleMusicLoginView { session in
                try model.connectAppleMusic(session)
                if purpose == .enableReverse {
                    model.setReverseEnabled(true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var reverseSyncDescription: String {
        if !model.ready { return "请先在首页读取 Apple Music 资料库并登录网易云音乐。" }
        if model.preview != nil { return "请先在首页完成或关闭当前同步预览。" }
        if !model.appleConnected {
            if model.reverseSwitchOn { return "反向同步已暂停，请在「账号」中登录 Apple Music。" }
            return "打开开关后，先登录 Apple Music。之后新增的网易云红心会同步到 Apple Music 资料库。"
        }
        return "开启后，网易云新增的红心会同步到 Apple Music 资料库。"
    }

    private func setReverseEnabled(_ enabled: Bool) {
        if enabled && !model.appleConnected {
            appleLogin = .enableReverse
        } else {
            model.setReverseEnabled(enabled)
        }
    }

    private func refreshSettings() {
        model.refreshLoginItem()
        Task { await model.notifications.refreshPermission() }
    }
}
