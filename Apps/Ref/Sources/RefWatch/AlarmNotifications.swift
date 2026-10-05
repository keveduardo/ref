import Foundation
import RefKit
import UserNotifications

/// The alarms, as scheduled watch notifications too — the backup that rings
/// when the app cannot (Kevin, 2026-10-04: half-time ran past its 5 minutes
/// with no buzz). The in-app haptic is a sleeping Task, and it only rings if
/// watchOS keeps the app running with the wrist down; a notification the
/// system holds rings regardless. When the app is in front it plays its own
/// rhythm, so the delegate keeps the notification quiet then.
enum AlarmNotifications {
    private static let prefix = "ref.alarm."

    /// Asked once, with Health — never at kick-off.
    static func requestAccess() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Replaces whatever was scheduled with these alerts (the next few).
    static func schedule(_ alerts: [MatchAlert]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<6).map { prefix + "\($0)" })
        for (index, alert) in alerts.prefix(6).enumerated() {
            let wait = alert.at.timeIntervalSinceNow
            guard wait > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = title(alert.kind)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            center.add(UNNotificationRequest(identifier: prefix + "\(index)", content: content, trigger: trigger))
        }
    }

    static func cancelAll() { schedule([]) }

    static func title(_ kind: MatchAlert.Kind) -> String {
        switch kind {
        case .halfLength(let half): half == 1 ? "First half — time" : "Second half — time"
        case .addedTimeUp: "Added time is up"
        case .halfTimeOver: "Half-time is up"
        case .quarterMark: "Quarter break"
        case .quarterBreakOver: "Quarter break is over"
        case .binOver: "Sin bin over"
        }
    }
}

/// Keeps a due notification quiet while the app is in front — the app has
/// already buzzed its own rhythm then.
/// `@unchecked Sendable`: no stored state at all, so one shared instance is
/// safe from any thread — Swift 6 asks for it on a `static let`.
final class AlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = AlarmNotificationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        []
    }
}
