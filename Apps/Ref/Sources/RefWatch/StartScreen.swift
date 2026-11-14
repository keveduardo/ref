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

    /// "Fri 6:00 PM · AR": the kick-off, and the referee's own slot if known.
    static func whenLine(_ setup: MatchSetup) -> String? {
        var parts: [String] = []
        if let kickOff = setup.kickOff {
            parts.append(kickOff.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        }
        if let role = setup.myRole { parts.append(role.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationDestination(for: UUID.self) { id in
                    if let setup = session.offers.first(where: { $0.id == id }) {
                        GameScreen(session: session, setup: setup)
                    }
                }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                if !session.offers.isEmpty {
                    Text("From the phone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(session.offers, id: \.id) { setup in
                        // A tap opens the game — teams, crew — and Start
                        // is there (Kevin, 2026-11-14: "when I click on a
                        // game … see the assigned referees").
                        NavigationLink(value: setup.id) {
                            VStack(spacing: 2) {
                                Text("\(setup.home.abbreviation) vs \(setup.away.abbreviation)")
                                    .font(.body.bold())
                                // Two games at one field look alike — the kick-off
                                // tells them apart (Kevin, 2026-11-12: "I can't
                                // see which match is 6p and which is 7p").
                                if let line = Self.whenLine(setup) {
                                    Text(line)
                                        .font(.headline)
                                        .foregroundStyle(.yellow)
                                }
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

/// One game from the phone's list: who, when, where, the crew — and Start.
struct GameScreen: View {
    let session: MatchSession
    let setup: MatchSetup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(setup.home.name) vs \(setup.away.name)")
                    .font(.headline)
                if let line = StartScreen.whenLine(setup) {
                    Text(line)
                        .font(.footnote.bold())
                        .foregroundStyle(.yellow)
                }
                if let competition = setup.competition, !competition.isEmpty {
                    Text(competition)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Referees")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                let crew = Self.crew(setup)
                if crew.isEmpty {
                    Text("None listed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(crew, id: \.slot) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.slot)
                                .font(.footnote.bold())
                                .foregroundStyle(row.isMe ? .yellow : .secondary)
                                .frame(width: 32, alignment: .leading)
                            Text(row.name)
                                .font(.footnote)
                                .foregroundStyle(row.isMe ? .yellow : .primary)
                            if row.isMe {
                                Text("You").font(.system(size: 11).bold()).foregroundStyle(.yellow)
                            }
                        }
                    }
                }

                Button {
                    Haptics.play(.start)
                    session.assign(Match(setup: setup))
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The filled slots, in order. "You" marks the referee's own — an AR
    /// without a number matches either assistant's slot only by name, so it
    /// is not marked.
    static func crew(_ setup: MatchSetup) -> [CrewRow] {
        let slots: [(slot: String, name: String?, role: RefereeRole)] = [
            ("CR", setup.cr, .cr), ("AR1", setup.ar1, .ar1), ("AR2", setup.ar2, .ar2)]
        return slots.compactMap { entry in
            guard let name = entry.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return CrewRow(slot: entry.slot, name: name, isMe: setup.myRole == entry.role)
        }
    }

    struct CrewRow: Hashable {
        let slot: String
        let name: String
        let isMe: Bool
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
