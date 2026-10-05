import RefKit
import SwiftUI

/// The alarm going off: what it is, the step it calls for, and Stop. It
/// stays — buzzing every few seconds — until one of the two is tapped.
struct AlarmScreen: View {
    let session: MatchSession

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let step {
                Button(step.label) {
                    Haptics.play(.click)
                    step.action()
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Stop") {
                Haptics.play(.click)
                session.stopAlarm()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(.horizontal, 4)
    }

    private var kind: MatchAlert.Kind? { session.ringing?.kind }

    private var title: String {
        guard let kind else { return "" }
        if case .halfLength(let half) = kind, half >= session.clock.config.halves {
            return "Time — end of the match"
        }
        return AlarmNotifications.title(kind)
    }

    /// The step the alarm calls for; taking it stops the alarm too.
    private var step: (label: String, action: @MainActor () -> Void)? {
        guard let kind else { return nil }
        switch kind {
        case .halfLength(let half), .addedTimeUp(let half):
            return half >= session.clock.config.halves
                ? ("End match", { session.fullTime() })
                : ("End half", { session.endHalf() })
        case .quarterMark:
            return ("Start quarter break", { session.startQuarterBreak() })
        case .halfTimeOver, .quarterBreakOver, .binOver:
            // Half-time over only silences: kicking off the second half stays
            // its own deliberate tap on the break screen (Kevin, 2026-10-05).
            return nil
        }
    }
}
