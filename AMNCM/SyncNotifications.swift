import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class SyncNotifications {
    enum Kind {
        case success, failure

        var preference: String {
            switch self {
            case .success: "notifyOnSyncSuccess"
            case .failure: "notifyOnSyncFailure"
            }
        }
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private(set) var success = UserDefaults.standard.bool(forKey: Kind.success.preference)
    private(set) var failure = UserDefaults.standard.bool(forKey: Kind.failure.preference)
    private(set) var requesting = false
    private(set) var message: String?

    func set(_ kind: Kind, enabled: Bool) {
        guard !requesting else { return }
        if !enabled {
            save(kind, enabled: false)
            return
        }
        requesting = true
        message = nil
        Task {
            defer { requesting = false }
            do {
                if try await center.requestAuthorization(options: [.alert, .sound]) {
                    save(kind, enabled: true)
                } else {
                    message = "请在「系统设置 → 通知 → AM-NCM」中允许通知，再开启此选项。"
                }
            } catch {
                message = "暂时无法请求通知权限，请稍后重试。"
            }
        }
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied && (success || failure) {
            message = "请在「系统设置 → 通知 → AM-NCM」中允许通知。"
        } else if settings.authorizationStatus == .authorized {
            message = nil
        }
    }

    func deliver(_ kind: Kind, title: String, body: String) {
        guard kind == .success ? success : failure else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
            } catch {
                message = "暂时无法发送通知，请检查 macOS 通知设置。"
            }
        }
    }

    private func save(_ kind: Kind, enabled: Bool) {
        switch kind {
        case .success: success = enabled
        case .failure: failure = enabled
        }
        defaults.set(enabled, forKey: kind.preference)
    }
}
