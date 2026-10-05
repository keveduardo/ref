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

    /// How many times, and how often, each alarm's notification repeats —
    /// "until I deactivate", within watchOS's 64 pending notifications:
    /// the ringing alarm and the next three, twelve each.
    private static let repeats = 12
    private static let every: TimeInterval = 20
    static let category = "ref.alarm"
    static let stopAction = "ref.alarm.stop"

    /// The Stop button on the notification itself.
    static func registerCategory() {
        let stop = UNNotificationAction(identifier: stopAction, title: "Stop", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [stop], intentIdentifiers: [])])
    }

    /// Replaces whatever was scheduled: the alarm ringing now (its remaining
    /// repeats) and the next three, each repeating until stopped.
    static func schedule(_ upcoming: [MatchAlert], ringing: MatchAlert? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)
        var slots: [(slot: Int, alert: MatchAlert)] = []
        if let ringing { slots.append((0, ringing)) }
        for (i, alert) in upcoming.prefix(3).enumerated() { slots.append((i + 1, alert)) }
        for (slot, alert) in slots {
            for r in 0..<repeats {
                let wait = alert.at.timeIntervalSinceNow + Double(r) * every
                guard wait > 1 else { continue }
                let content = UNMutableNotificationContent()
                content.title = title(alert.kind)
                content.body = "Tap Stop to silence it."
                content.sound = .default
                content.categoryIdentifier = category
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
                center.add(UNNotificationRequest(identifier: "\(prefix)\(slot).\(r)", content: content, trigger: trigger))
            }
        }
    }

    private static var allIdentifiers: [String] {
        (0...3).flatMap { slot in (0..<repeats).map { "\(prefix)\(slot).\($0)" } }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allIdentifiers)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

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
    /// Set by the root screen: what Stop does.
    var onStop: (@MainActor @Sendable () -> Void)?

    /// The notification's Stop button.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == AlarmNotifications.stopAction else { return }
        let stop = onStop
        await MainActor.run { stop?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        []
    }
}
