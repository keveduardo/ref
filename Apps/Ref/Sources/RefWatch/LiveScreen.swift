import RefKit
import SwiftUI
import WatchKit

/// The live match face — the screen the referee stares at for ninety minutes.
///
/// Every number is recomputed from `now` on a `TimelineView` tick, never from
/// a stored ticker, so it is right after the wrist has been down and after a
/// relaunch. Under the always-on display the face keeps the clock and score
/// and drops everything the referee cannot reach anyway.
struct LiveScreen: View {
    let session: MatchSession

    @State private var showingRecord = false
    @State private var confirmingFullTime = false
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let clock = session.clock
            VStack(spacing: 2) {
                scoreRow
                Text(clock.text(at: now))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                Text(periodLabel(clock, at: now))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !dimmed {
                    healthRow
                    controls(clock, at: now)
                }
            }
        }
        .sheet(isPresented: $showingRecord) { RecordFlow(session: session) }
        .confirmationDialog("Full time?", isPresented: $confirmingFullTime) {
            Button("End the match", role: .destructive) { session.fullTime() }
        }
    }

    // MARK: - Pieces

    private var scoreRow: some View {
        HStack(spacing: 6) {
            if let setup = session.match?.setup {
                Text(setup.home.abbreviation)
                    .foregroundStyle(setup.home.color.watchColor)
                Text(session.score.text)
                    .font(.title3.bold())
                    .monospacedDigit()
                Text(setup.away.abbreviation)
                    .foregroundStyle(setup.away.color.watchColor)
            }
        }
        .font(.headline)
    }

    private func periodLabel(_ clock: MatchClock, at now: Date) -> String {
        switch clock.phase(at: now) {
        case .notStarted: return "Ready to kick off"
        case .running(let half): return half == 1 ? "1st half" : half == 2 ? "2nd half" : "Half \(half)"
        case .paused(let half): return "Paused — half \(half)"
        case .halfTime: return "Half time"
        case .fullTime: return "Full time"
        }
    }

    /// The referee's own heart rate, when the workout is running — the one
    /// health number worth a glance mid-match.
    @ViewBuilder
    private var healthRow: some View {
        if let heartRate = session.workout.heartRate {
            Text("♥ \(Int(heartRate))")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    @ViewBuilder
    private func controls(_ clock: MatchClock, at now: Date) -> some View {
        switch clock.phase(at: now) {
        case .notStarted:
            Button("Kick off") {
                Haptics.play(.start)
                session.kickOff()
            }
            .buttonStyle(.borderedProminent)
        case .running:
            HStack(spacing: 6) {
                Button {
                    Haptics.play(.click)
                    session.tapAddedTime()
                } label: {
                    Text("+1′").monospacedDigit()
                }
                Button {
                    showingRecord = true
                } label: {
                    Text("Record")
                }
                .tint(.green)
                Button {
                    Haptics.play(.click)
                    if clock.currentHalf(at: now) < clock.config.halves {
                        session.endHalf()
                    } else {
                        confirmingFullTime = true
                    }
                } label: {
                    Image(systemName: "flag.checkered")
                }
            }
            .font(.footnote)
        default:
            EmptyView()
        }
    }
}

/// Haptics, in one place, so every recorded incident feels the same.
enum Haptics {
    static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    /// A goal, a card, a substitution — the tap that must be felt through a
    /// sleeve.
    static func recorded() {
        play(.notification)
    }

    /// The alarms, each with its own rhythm so the referee knows which one
    /// it is without looking: the half's length is three long buzzes, the
    /// added time used up is two, the break over is three rising taps, and a
    /// sin bin over is a rising pair.
    @MainActor
    static func alert(_ kind: MatchAlert.Kind) async {
        let (type, count): (WKHapticType, Int)
        switch kind {
        case .halfLength: (type, count) = (.notification, 3)
        case .addedTimeUp: (type, count) = (.notification, 2)
        case .halfTimeOver: (type, count) = (.directionUp, 3)
        case .binOver: (type, count) = (.directionUp, 2)
        }
        for index in 0..<count {
            if index > 0 { try? await Task.sleep(for: .milliseconds(700)) }
            play(type)
        }
    }
}
