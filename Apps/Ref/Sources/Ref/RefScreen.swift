import RefKit
import SwiftUI

/// The phone's home: the shelf of matches, the teams, the season, the
/// settings. Set a match up here, record it on the watch, read it back here.
struct RefScreen: View {
    let store: PhoneStore
    let link: PhoneLink
    let account: AccountStore

    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("ref.halfMinutes") private var halfMinutes = MatchDefaults.standard.halfMinutes
    @AppStorage("ref.halfTimeMinutes") private var halfTimeMinutes = MatchDefaults.standard.halfTimeMinutes
    @AppStorage("ref.addedTimeButton") private var addedTimeButton = false
    @AppStorage("ref.quarterBreak") private var quarterBreak = false
    @AppStorage("ref.quarterBreakMinutes") private var quarterBreakMinutes = 2

    var body: some View {
        TabView {
            MatchesScreen(store: store)
                .tabItem { Label("Matches", systemImage: "soccerball") }
            TeamsScreen(store: store)
                .tabItem { Label("Teams", systemImage: "person.3") }
            StatsScreen(store: store)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
            SettingsScreen(link: link, account: account)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        // Activation completes after launch, so the first push goes then;
        // after that, whenever the matches or the defaults change.
        .onChange(of: link.activated, initial: true) { _, _ in pushAssignment() }
        .onChange(of: store.upcoming.map(\.setup)) { _, _ in pushAssignment() }
        .onChange(of: halfMinutes) { _, _ in pushAssignment() }
        .onChange(of: halfTimeMinutes) { _, _ in pushAssignment() }
        .onChange(of: addedTimeButton) { _, _ in pushAssignment() }
        // Back in the foreground: pick up what changed on another phone.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.sync() } }
        }
        .onChange(of: quarterBreak) { _, _ in pushAssignment() }
        .onChange(of: quarterBreakMinutes) { _, _ in pushAssignment() }
    }

    /// The watch always has the newest set of matches to offer.
    private func pushAssignment() {
        link.sendAssignment(store.upcoming.map(\.setup),
                            defaults: MatchDefaults(halfMinutes: halfMinutes,
                                                    halfTimeMinutes: halfTimeMinutes,
                                                    addedTimeButton: addedTimeButton,
                                                    quarterBreak: quarterBreak
                                                        ? QuarterBreak(breakMinutes: quarterBreakMinutes) : nil))
    }
}

struct MatchesScreen: View {
    let store: PhoneStore
    @State private var settingUp = false
    @State private var importResult: String?
    /// The match just deleted by a swipe, kept for a few seconds so a full
    /// swipe by accident can be taken back.
    @State private var recentlyDeleted: Match?

    var body: some View {
        NavigationStack {
            List {
                if store.upcoming.isEmpty && store.played.isEmpty && store.onWatch.isEmpty {
                    ContentUnavailableView(
                        "No matches yet", systemImage: "soccerball",
                        description: Text("Set one up and it goes to the watch."))
                }
                if !store.onWatch.isEmpty {
                    Section {
                        ForEach(store.onWatch) { match in
                            NavigationLink(value: match.id) { MatchRow(match: match) }
                                .modifier(SwipeToDelete { delete(match) })
                        }
                    } header: {
                        Text("On the watch")
                    } footer: {
                        Text("Started on the watch. Tap to name the teams and pick colours; the watch picks the changes up.")
                    }
                }
                if !store.upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(store.upcoming) { match in
                            NavigationLink(value: match.id) { MatchRow(match: match) }
                                .modifier(SwipeToDelete { delete(match) })
                        }
                    }
                }
                if !store.played.isEmpty {
                    Section("Played") {
                        ForEach(store.played) { match in
                            NavigationLink(value: match.id) { MatchRow(match: match) }
                                .modifier(SwipeToDelete { delete(match) })
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
                    Menu {
                        Button {
                            settingUp = true
                        } label: {
                            Label("New match", systemImage: "plus")
                        }
                        Button {
                            pasteReminder()
                        } label: {
                            Label("Paste reminder email", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $settingUp) {
                MatchSetupScreen(store: store)
            }
            .safeAreaInset(edge: .bottom) {
                if let match = recentlyDeleted {
                    HStack {
                        Text("Deleted \(match.setup.home.abbreviation) vs \(match.setup.away.abbreviation)")
                            .font(.subheadline)
                        Spacer()
                        Button("Undo") {
                            store.save(match)
                            recentlyDeleted = nil
                        }
                        .bold()
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: recentlyDeleted?.id)
            .alert(importResult ?? "", isPresented: Binding(
                get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {
                Button("OK") { importResult = nil }
            }
        }
    }
}

extension MatchesScreen {
    /// The text of a scheduler's reminder email, copied in Mail or Gmail,
    /// becomes upcoming matches — CGI Sports has no calendar feed to
    /// subscribe to, but its reminders are one field per line.
    fileprivate func pasteReminder() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            importResult = "Nothing to paste. Copy the text of a game reminder email first."
            return
        }
        let result = store.importGames(from: text)
        switch (result.new, result.found) {
        case (_, 0):
            importResult = "No games found. Copy the whole reminder, from \u{201C}Game ID\u{201D} to \u{201C}Visitor\u{201D}."
        case (0, _):
            importResult = "Already on your list."
        case (1, _):
            importResult = "1 match added."
        case (let n, _):
            importResult = "\(n) matches added."
        }
    }
}

extension MatchesScreen {
    fileprivate func delete(_ match: Match) {
        store.delete(match)
        recentlyDeleted = match
        let id = match.id
        Task {
            try? await Task.sleep(for: .seconds(5))
            if recentlyDeleted?.id == id { recentlyDeleted = nil }
        }
    }
}

/// Swipe left to delete, the iOS way. A long swipe deletes at once; the
/// Matches screen offers Undo for a few seconds after.
struct SwipeToDelete: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Delete", systemImage: "trash", role: .destructive, action: action)
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
