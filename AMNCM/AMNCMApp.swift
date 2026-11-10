import SwiftUI
import UserNotifications

@main
struct AMNCMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SyncModel()

    var body: some Scene {
        Window("AM-NCM", id: "main") {
            HomeView(model: model)
                .frame(minWidth: HomeView.windowWidth, minHeight: 300)
                .task {
                    appDelegate.onTerminate = { model.stop() }
                    model.start()
                    await model.updates.checkIfDue()
                }
        }
        .defaultSize(width: HomeView.windowWidth, height: HomeView.defaultContentHeight)
        .commands { SettingsCommands(model: model) }

        Window("匹配明细", id: "report") {
            ReportView(reportVersion: model.reportVersion)
                .frame(minWidth: 1080, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 680)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .commands { ReportZoomCommands() }

        MenuBarExtra {
            SyncMenuView(model: model)
        } label: {
            Image(systemName: model.operation == nil ? "music.note" : "arrow.trianglehead.clockwise")
                .accessibilityLabel("AM-NCM")
        }

    }
}

private struct SettingsCommands: Commands {
    let model: SyncModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: "main")
                model.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }


    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
