import RefKit
import SwiftUI

/// The live match face. P0 proves two things the real screen (P2) will lean
/// on: the kit crosses into the watch app, and the face is driven by a
/// `TimelineView` recomputed from `now` — never a stored ticker, so it reads
/// correctly after the wrist has been down and under the always-on display.
struct LiveScreen: View {
    @State private var link = WatchLink()

    private let clock: MatchClock

    init() {
        // Kick-off a plausible 12:34 ago, so a render screenshot shows a face
        // that looks like a match rather than 0:00.
        let start = Date().addingTimeInterval(-(12 * 60 + 34))
        clock = MatchClock.replay(config: .adult,
                                  events: [MatchEvent(at: start, kind: .kickOff(half: 1))])
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(clock.text(at: context.date))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                Text(link.activated ? "P0 · linked" : "P0 · no phone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The watch's home: today's match from the phone, or a quick start. P2.
struct StartScreen: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "soccerball")
            Text("Today's match")
                .font(.headline)
            Text("From the phone in P4; quick start in P2.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
