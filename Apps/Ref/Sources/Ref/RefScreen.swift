import RefKit
import SwiftUI

/// The phone's home: the shelf of matches, the teams, the season, the
/// settings. Set a match up here, record it on the watch, read it back here.
struct RefScreen: View {
    let store: PhoneStore
    let link: PhoneLink

    @AppStorage("ref.halfMinutes") private var halfMinutes = MatchDefaults.standard.halfMinutes
    @AppStorage("ref.halfTimeMinutes") private var halfTimeMinutes = MatchDefaults.standard.halfTimeMinutes

    var body: some View {
        TabView {
            MatchesScreen(store: store)
                .tabItem { Label("Matches", systemImage: "soccerball") }
            TeamsScreen(store: store)
                .tabItem { Label("Teams", systemImage: "person.3") }
            StatsScreen(store: store)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
            SettingsScreen(link: link)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        // Activation completes after launch, so the first push goes then;
        // after that, whenever the matches or the defaults change.
        .onChange(of: link.activated, initial: true) { _, _ in pushAssignment() }
        .onChange(of: store.upcoming.map(\.setup)) { _, _ in pushAssignment() }
        .onChange(of: halfMinutes) { _, _ in pushAssignment() }
        .onChange(of: halfTimeMinutes) { _, _ in pushAssignment() }
    }

    /// The watch always has the newest set of matches to offer.
    private func pushAssignment() {
        link.sendAssignment(store.upcoming.map(\.setup),
                            defaults: MatchDefaults(halfMinutes: halfMinutes,
                                                    halfTimeMinutes: halfTimeMinutes))
    }
}

struct MatchesScreen: View {
    let store: PhoneStore
    @State private var settingUp = false

    var body: some View {
        NavigationStack {
            List {
                if store.upcoming.isEmpty && store.played.isEmpty {
                    ContentUnavailableView(
                        "No matches yet", systemImage: "soccerball",
                        description: Text("Set one up and it goes to the watch."))
                }
                if !store.upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(store.upcoming) { match in
                            NavigationLink(value: match.id) { MatchRow(match: match) }
                        }
                    }
                }
                if !store.played.isEmpty {
                    Section("Played") {
                        ForEach(store.played) { match in
                            NavigationLink(value: match.id) { MatchRow(match: match) }
                        }
                    }
                }
            }
            .navigationTitle("RefTime")
            .navigationDestination(for: UUID.self) { id in
                if let match = store.all.first(where: { $0.id == id }) {
                    MatchDetailScreen(store: store, match: match)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        settingUp = true
                    } label: {
                        Label("New match", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $settingUp) {
                MatchSetupScreen(store: store)
            }
        }
    }
}

struct MatchRow: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if match.isFinished {
                    Text(match.setup.home.abbreviation)
                        .foregroundStyle(match.setup.home.color.phoneColorInk)
                    Text(match.score.text)
                        .font(.body.bold())
                        .monospacedDigit()
                    Text(match.setup.away.abbreviation)
                        .foregroundStyle(match.setup.away.color.phoneColorInk)
                } else {
                    Text("\(match.setup.home.abbreviation) vs \(match.setup.away.abbreviation)")
                        .font(.body.bold())
                }
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let when = (match.setup.kickOff ?? match.createdAt)
        let date = when.formatted(date: .abbreviated, time: .shortened)
        if let competition = match.setup.competition, !competition.isEmpty {
            return "\(competition) · \(date)"
        }
        return date
    }
}
