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
    /// Until when the buttons show under the clock. ! The face changes only
    /// when touched (Kevin, 2026-11-06: "I'd rather have the screen only
    /// change if I actually touch it, otherwise the big number should stay
    /// persistent"). The buttons used to appear with every wrist raise and
    /// squeeze the clock small; now a tap shows them for a few seconds.
    @State private var controlsUntil: Date?
    private static let controlsFor: TimeInterval = 8
    /// How long after the quarter mark its button waits to be taken. The
    /// break is called at the next stoppage, not on the minute; past this
    /// it was run without the watch, and the button goes (2026-11-06: it
    /// used to stay, big and orange, to the end of the half).
    private static let quarterButtonFor: TimeInterval = 5 * 60

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
            let phase = clock.phase(at: now)
            // Before kick-off the buttons are the point; once the clock runs,
            // they wait for a tap. The wrist alone never changes the face.
            let showingControls: Bool = {
                guard !dimmed else { return false }
                if case .running = phase { return (controlsUntil ?? .distantPast) > now }
                return true
            }()
            VStack(spacing: 2) {
                scoreRow
                Text(clock.text(at: now))
                    .font(.system(size: showingControls ? 40 : 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // Orange while stopped, so a paused clock is never read as a running one.
                    .foregroundStyle(phase.isRunning ? Color.primary : (phase == .notStarted ? .primary : .orange))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(periodLabel(clock, at: now))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                breakCountdown(clock, at: now)
                // A match timed without a running workout can lose the
                // screen to the watch face; say so rather than let it.
                if case .running = phase, !session.workout.isRunning,
                   let kickOff = session.match?.events.events.first?.at, now.timeIntervalSince(kickOff) > 15 {
                    Text("Workout off — may not stay on screen")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if showingControls {
                    healthRow
                    controls(clock, at: now)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Buttons take their own taps first; a tap anywhere else shows
            // them, or keeps them a little longer.
            .onTapGesture { controlsUntil = Date().addingTimeInterval(Self.controlsFor) }
        }
        .onChange(of: dimmed) { _, isDimmed in if isDimmed { controlsUntil = nil } }
    }

    /// The quarter break's own timer, under the clock whatever the wrist or
    /// the buttons are doing: it is a number to read, like the clock.
    @ViewBuilder
    private func breakCountdown(_ clock: MatchClock, at now: Date) -> some View {
        if case .running(let half) = clock.phase(at: now),
           let quarter = session.match?.setup.quarterBreak, let match = session.match,
           let taken = match.events.quarterBreak(inHalf: half), !match.events.quarterBreakEnded(inHalf: half) {
            let left = TimeInterval(quarter.breakMinutes * 60) - now.timeIntervalSince(taken.at)
            if left > 0 {
                Text("Break \(ClockFormat.mmss(left))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
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
                let elapsed = clock.elapsed(inHalf: half, at: now)
                let mark = quarter.mark(halfLength: clock.config.halfLength)
                if let taken = match.events.quarterBreak(inHalf: half) {
                    // Its timer is under the clock (breakCountdown); End
                    // finishes it early. Gone at zero — the alarm takes over
                    // then (Kevin, 2026-10-05).
                    let left = TimeInterval(quarter.breakMinutes * 60) - now.timeIntervalSince(taken.at)
                    if left > 0, !match.events.quarterBreakEnded(inHalf: half) {
                        Button("End break") {
                            Haptics.play(.click)
                            session.endQuarterBreak()
                        }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                } else if elapsed >= mark, elapsed < min(mark + Self.quarterButtonFor, clock.config.halfLength) {
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
            //
            // ! Record and Pause (Kevin, 2026-11-06: "I don't think I need an
            // end the half button there. Maybe just record and pause"). End
            // half comes back once the half's time is up — the alarm offers
            // it then too — and from a pause.
            let lastHalf = clock.currentHalf(at: now) >= clock.config.halves
            let timeUp = clock.elapsed(inHalf: half, at: now) >= clock.config.halfLength
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
                if timeUp {
                    endHalfButton(lastHalf: lastHalf)
                } else {
                    Button {
                        Haptics.play(.stop)
                        session.pauseClock()
                    } label: {
                        Text("Pause")
                    }
                    .tint(.orange)
                }
            }
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        case .paused:
            // Paused is a state to act on, so its buttons stay up untouched.
            let lastHalf = clock.currentHalf(at: now) >= clock.config.halves
            Button {
                Haptics.play(.start)
                session.resumeClock()
            } label: {
                Text("Resume")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            endHalfButton(lastHalf: lastHalf)
                .font(.footnote)
        default:
            EmptyView()
        }
    }
}

extension LiveScreen {
    /// End half — or End match, which asks first — on its own tap.
    fileprivate func endHalfButton(lastHalf: Bool) -> some View {
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
