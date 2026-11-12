import Foundation
import UserNotifications

/// Local notifications ("installation finished"). Nothing leaves the Mac.
public protocol Notifying: Sendable {
    func notify(title: String, body: String) async
}

/// Posts notifications through the system. The permission prompt appears the first time one is needed.
struct SystemNotifier: Notifying {
    func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Used by previews and tests: never posts anything.
struct SilentNotifier: Notifying {
    func notify(title: String, body: String) async {}
}
