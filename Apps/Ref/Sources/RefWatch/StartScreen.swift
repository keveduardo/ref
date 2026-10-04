import RefKit
import SwiftUI
import WatchKit

/// The watch's home: today's match from the phone, or a quick start.
struct StartScreen: View {
    let session: MatchSession
    /// False in the render job: a system authorization sheet must not land in
    /// a screenshot.
    var requestsAccess = true

    @State private var choosingDivision = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if !session.offers.isEmpty {
                    Text("From the phone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(session.offers, id: \.id) { setup in
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

                if session.offers.isEmpty {
                    // Alone, quick start is the way in.
                    Button("Quick start") {
                        choosingDivision = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Quick start") {
                        choosingDivision = true
                    }
                    .buttonStyle(.bordered)
                }

                Text("Quick start asks the age group. Matches set up on the phone appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .sheet(isPresented: $choosingDivision) {
            QuickStartList(session: session)
        }
        .task {
            // One system sheet, now — never at kick-off.
            if requestsAccess {
                await session.requestHealthAccess()
            }
        }
    }
}

/// Quick start's one question: which division. The AYSO presets first, then
/// "Other" for the phone's defaults.
struct QuickStartList: View {
    let session: MatchSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(MatchFormat.presets) { format in
                Button {
                    start(format)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(format.title.replacingOccurrences(of: "AYSO ", with: ""))
                            .font(.body.bold())
                        Text("\(format.halfMinutes)-min halves · \(format.playersPerSide) a side")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                start(nil)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Other").font(.body.bold())
                    Text("\(session.link.defaults.halfMinutes)-min halves")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Age group")
    }

    private func start(_ format: MatchFormat?) {
        Haptics.play(.start)
        session.startQuick(format)
        dismiss()
    }
}
