import SwiftUI

@main
struct AMNCMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SyncModel()

    var body: some Scene {
        Window("AM-NCM", id: "main") {
            HomeView(model: model)
                .frame(minWidth: 570, minHeight: 530)
                .task {
                    appDelegate.onTerminate = { model.stop() }
                    model.start()
                }
        }
        .defaultSize(width: 660, height: 650)

        Window("匹配明细", id: "report") {
            ReportView(reportVersion: model.reportVersion)
                .frame(minWidth: 850, minHeight: 470)
        }
        .defaultSize(width: 1120, height: 680)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            SyncMenuView(model: model)
        } label: {
            Image(systemName: model.operation == nil ? "music.note" : "arrow.trianglehead.clockwise")
                .accessibilityLabel("AM-NCM")
        }

        Settings {
            SyncSettingsView(model: model)
        }
    }
}


private final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
