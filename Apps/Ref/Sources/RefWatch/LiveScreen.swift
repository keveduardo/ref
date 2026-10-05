import RefKit
import SwiftUI
import WatchKit

/// The live match face — the screen the referee stares at for ninety minutes.
///
/// Every number is recomputed from `now` on a `TimelineView` tick, never from
/// a stored ticker, so it is right after the wrist has been down and after a
/// relaunch. Under the always-on display the face keeps the clock and score
/// and drops everything the referee cannot reach anyway.
///
/// Once the match is under way it is the middle of three pages: swipe right
/// for the home team's incidents, left for the away team's (Kevin's layout,
/// 2026-10-04). A recording on either returns here.
struct LiveScreen: View {
    let session: MatchSession

    /// 0 home, 1 the face, 2 away.
    @State private var page = 1
    /// Bumped on every return to the face, so a team page left halfway
    /// through a recording starts at its menu next time.
    @State private var visits = 0
    @State private var showingRecord = false
    @State private var confirmingFullTime = false
    @State private var markingField = false
    @State private var confirmingChange = false
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Group {
            if session.stage == .live {
                TabView(selection: $page) {
                    RecordFlow(session: session, side: .home, onDone: { page = 1 })
                        .id("home-\(visits)")
                        .tag(0)
                    face.tag(1)
                    RecordFlow(session: session, side: .away, onDone: { page = 1 })
                        .id("away-\(visits)")
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: page) { _, now in if now == 1 { visits += 1 } }
            } else {
                face
            }
        }
        .sheet(isPresented: $showingRecord) { RecordFlow(session: session) }
        .sheet(isPresented: $markingField) { MarkFieldScreen(session: session) }
        .confirmationDialog("Full time?", isPresented: $confirmingFullTime) {
            Button("End the match", role: .destructive) { session.fullTime() }
        }
        .confirmationDialog("Choose another match?", isPresented: $confirmingChange) {
            Button("Back to the list") { session.discard() }
        }
    }

    private var face: some View {
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
    }

    // MARK: - Pieces

    private var scoreRow: some View {
        HStack(spacing: 6) {
            if let setup = session.match?.setup {
                Text(setup.home.abbreviation)
                    .foregroundStyle(setup.home.color.watchColor)
                // 7U and 8U keep no score (Region 34), so the face shows none.
                if setup.format?.keepsScore == false {
                    Text("vs").foregroundStyle(.secondary)
                } else {
                    Text(session.score.text)
                        .font(.title3.bold())
                        .monospacedDigit()
                }
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
            if let format = session.match?.setup.format {
                Text(format.watchReminder)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Button("Kick off") {
                Haptics.play(.start)
                session.kickOff()
            }
            .buttonStyle(.borderedProminent)
            // Optional, before kick-off: the frame for the pitch diagram.
            Button {
                markingField = true
            } label: {
                Label(session.match?.pitch == nil ? "Mark field" : "Field marked",
                      systemImage: session.match?.pitch == nil ? "scope" : "checkmark.circle")
            }
            .font(.footnote)
            // Before kick-off only: back to the list — quick start, or the
            // phone's matches (Kevin couldn't find them once one was picked).
            Button("Choose another match") { confirmingChange = true }
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .running(let half):
            // The quarter break: its button from the mark until it is taken,
            // then its own timer while it runs. The match clock never stops.
            if let quarter = session.match?.setup.quarterBreak, let match = session.match {
                if let taken = match.events.quarterBreak(inHalf: half) {
                    let length = TimeInterval(quarter.breakMinutes * 60)
                    let into = now.timeIntervalSince(taken.at)
                    if into < length + 60 {
                        Text("Break \(ClockFormat.mmss(into)) of \(quarter.breakMinutes):00")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(into >= length ? .orange : .secondary)
                    }
                } else if clock.elapsed(inHalf: half, at: now) >= quarter.mark(halfLength: clock.config.halfLength),
                          clock.elapsed(inHalf: half, at: now) < clock.config.halfLength {
                    Button("Quarter break") {
                        Haptics.play(.stop)
                        session.startQuarterBreak()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .font(.footnote)
                }
            }
            // Words, not symbols: "+1′" and a chequered flag had to be
            // explained (Kevin, 2026-10-04).
            let lastHalf = clock.currentHalf(at: now) >= clock.config.halves
            HStack(spacing: 4) {
                // Only when the match announces added time — off by default.
                if session.match?.setup.addedTimeButton == true {
                    Button {
                        Haptics.play(.click)
                        session.tapAddedTime()
                    } label: {
                        Text("+1 min")
                    }
                }
                Button {
                    showingRecord = true
                } label: {
                    Text("Record")
                }
                .tint(.green)
                Button {
                    Haptics.play(.click)
                    if lastHalf {
                        confirmingFullTime = true
                    } else {
                        session.endHalf()
                    }
                } label: {
                    Text(lastHalf ? "End match" : "End half")
                }
            }
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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

    /// The alarm burst: the strongest patterns watchOS has (`.failure` and
    /// `.retry`), six back to back — Kevin found the gentle rhythms too weak
    /// to feel on the pitch (2026-10-05). Watch apps cannot set intensity;
    /// Settings › Sounds & Haptics › Prominent Haptic is the other lever.
    /// The alarm screen says which alarm it is.
    @MainActor
    static func alert(_ kind: MatchAlert.Kind) async {
        let pattern: [WKHapticType] = [.failure, .retry, .failure, .retry, .failure, .retry]
        for (index, type) in pattern.enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(450)) }
            play(type)
        }
    }
}
