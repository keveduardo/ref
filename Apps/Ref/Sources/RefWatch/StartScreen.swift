import RefKit
import SwiftUI
import WatchKit

/// The watch's home: today's match from the phone, or a quick start.
struct StartScreen: View {
    let session: MatchSession
    /// False in the render job: a system authorization sheet must not land in
    /// a screenshot.
    var requestsAccess = true

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if !session.link.assignments.isEmpty {
                    Text("From the phone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(session.link.assignments, id: \.id) { setup in
                        Button {
                            Haptics.play(.start)
                            session.assign(Match(setup: setup))
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(setup.home.abbreviation) vs \(setup.away.abbreviation)")
                                    .font(.body.bold())
                                if let competition = setup.competition, !competition.isEmpty {
                                    Text(competition)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Image(systemName: "soccerball")
                }

                if session.link.assignments.isEmpty {
                    // Alone, quick start is the way in.
                    Button("Quick start") {
                        Haptics.play(.start)
                        session.startQuick()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Quick start") {
                        Haptics.play(.start)
                        session.startQuick()
                    }
                    .buttonStyle(.bordered)
                }

                Text("\(SessionSettings.halfMinutes)-minute halves. Matches set up on the phone appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .task {
            // One system sheet, now — never at kick-off.
            if requestsAccess {
                await session.requestHealthAccess()
            }
        }
    }
}
