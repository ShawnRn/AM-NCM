import SwiftUI

struct SyncMenuView: View {
    let model: SyncModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.operation != nil {
            Text(model.stage)
            if let counter = model.counter { Text(counter) }
        } else if let date = model.lastSync {
            Text("上次同步 \(date, format: .dateTime.month().day().hour().minute())")
        } else {
            Text(model.ready ? "可以同步" : "等待连接音乐服务")
        }
        Divider()
        Button("打开 AM-NCM") { openWindow(id: "main") }
        Button("预览同步") {
            openWindow(id: "main")
            model.prepareSync()
        }
        .disabled(!model.ready || model.operation != nil || model.preview != nil)
        SettingsLink()
        Divider()
        Button("退出 AM-NCM") { NSApp.terminate(nil) }
            .disabled(model.operation == .sync)
    }
}
