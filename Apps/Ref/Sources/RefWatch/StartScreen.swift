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

                // What the phone last sent, and how many — compare with the
                // phone's Settings › Watch › Last sent.
                if let updated = session.link.lastUpdated {
                    let n = session.link.assignments.count
                    Text("Updated from the phone \(updated.formatted(date: .omitted, time: .shortened)) · \(n) match\(n == 1 ? "" : "es")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Haptics.play(.click)
                    session.link.requestAssignment()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .font(.footnote)
                Text("Build \(WatchLink.build)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .sheet(isPresented: $choosingDivision) {
            QuickStartList(session: session)
        }
        .onAppear { session.link.requestAssignment() }
        .task {
            // One system sheet, now — never at kick-off.
            if requestsAccess {
                await session.requestHealthAccess()
            }
        }
    }
}

/// Quick start's question: which division — the age from a short list, then
/// girls or boys. "Other" takes the phone's defaults.
struct QuickStartList: View {
    let session: MatchSession

    @Environment(\.dismiss) private var dismiss
    @State private var age: Int?

    var body: some View {
        NavigationStack {
            List {
                ForEach(MatchFormat.ages, id: \.self) { age in
                    if let format = MatchFormat.preset(age: age, gender: .girls) {
                        Button {
                            self.age = age
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(age)U").font(.body.bold())
                                Text("\(format.halfMinutes)-min halves · \(format.playersPerSide) v \(format.playersPerSide)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
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
            .navigationDestination(item: $age) { age in
                VStack(spacing: 8) {
                    Text("\(age)U").font(.headline)
                    ForEach(MatchFormat.Gender.allCases, id: \.self) { gender in
                        Button(gender.title) {
                            start(MatchFormat.preset(age: age, gender: gender))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func start(_ format: MatchFormat?) {
        Haptics.play(.start)
        session.startQuick(format)
        dismiss()
    }
}
