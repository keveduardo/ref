import RefKit
import SwiftUI

/// The break: the score, how long it has been running, and the whistle that
/// starts the second half.
struct HalfTimeScreen: View {
    let session: MatchSession

    @State private var confirmingResume = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 3) {
                    Text("Half time")
                        .font(.headline)
                    if let elapsed = session.clock.halfTimeElapsed(at: context.date) {
                        Text(ClockFormat.mmss(elapsed))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    scoreLine
                    Button("Start 2nd half") {
                        Haptics.play(.start)
                        session.startNextHalf()
                    }
                    .buttonStyle(.borderedProminent)
                    // The flag on the live face has no confirmation — one tap
                    // must end a half — so a mis-tap is undone here instead.
                    if let half = session.resumableHalf {
                        Button(half == 1 ? "Resume 1st half" : "Resume half \(half)") {
                            confirmingResume = true
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .confirmationDialog("The half ended by mistake?", isPresented: $confirmingResume) {
            Button("Resume — the clock never stopped") {
                Haptics.play(.start)
                session.resumeHalf()
            }
        }
    }

    private var scoreLine: some View {
        HStack(spacing: 6) {
            if let setup = session.match?.setup {
                Text(setup.home.abbreviation).foregroundStyle(setup.home.color.watchColor)
                Text(session.score.text).font(.body.bold()).monospacedDigit()
                Text(setup.away.abbreviation).foregroundStyle(setup.away.color.watchColor)
            }
        }
        .font(.footnote)
    }
}

/// Full time: the score, the report so far, and the way out. Sending the
/// match to the phone joins this screen in P4.
struct SummaryScreen: View {
    let session: MatchSession

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Full time")
                    .font(.headline)
                if let setup = session.match?.setup {
                    HStack(spacing: 6) {
                        Text(setup.home.abbreviation).foregroundStyle(setup.home.color.watchColor)
                        Text(session.score.text).font(.title3.bold()).monospacedDigit()
                        Text(setup.away.abbreviation).foregroundStyle(setup.away.color.watchColor)
                    }
                    .font(.headline)
                }
                if let match = session.match {
                    let entries = match.report.timeline
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        // A half divider: the second half's minutes start over,
                        // so without it the list reads 45+3' then 28'.
                        if index > 0, entries[index - 1].half != entry.half {
                            Text(entry.halfTitle)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 3)
                        }
                        Text(entry.line)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(session.link.activated
                         ? "The report is on its way to the phone."
                         : "The report goes to the phone when it is near again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                Button("Done") {
                    Haptics.play(.click)
                    session.discard()
                }
                .padding(.top, 4)
            }
        }
    }
}
