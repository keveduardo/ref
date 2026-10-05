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
        // The look (Theme.swift): always dark, gold for what is selected,
        // a navy tab bar.
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .toolbarBackground(Theme.navy, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
                ScreenHeader(title: "Matches")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if store.upcoming.isEmpty && store.played.isEmpty && store.onWatch.isEmpty {
                    ContentUnavailableView(
                        "No matches yet", systemImage: "soccerball",
                        description: Text("Tap + to set one up, or quick start on the watch."))
                        .listRowBackground(Color.clear)
                }
                if !store.onWatch.isEmpty {
                    Section {
                        SectionTitle(symbol: "applewatch", title: "On the watch")
                        ForEach(store.onWatch) { match in
                            NavigationLink(value: match.id) { FixtureRow(match: match) }
                                .modifier(SwipeToDelete { delete(match) })
                        }
                    } footer: {
                        Text("Started on the watch. Tap to name the teams and pick colours.")
                            .foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.card)
                    .listRowSeparatorTint(Theme.goldEdge)
                }
                if !store.upcoming.isEmpty {
                    Section {
                        SectionTitle(symbol: "megaphone.fill", title: "Upcoming fixtures")
                        ForEach(store.upcoming) { match in
                            NavigationLink(value: match.id) { FixtureRow(match: match) }
                                .modifier(SwipeToDelete { delete(match) })
                        }
                    }
                    .listRowBackground(Theme.card)
                    .listRowSeparatorTint(Theme.goldEdge)
                }
                if !store.played.isEmpty {
                    Section {
                        SectionTitle(symbol: "trophy.fill", title: "Recent results")
                        ForEach(store.played) { match in
                            NavigationLink(value: match.id) { ResultRow(match: match) }
                                .modifier(SwipeToDelete { delete(match) })
                        }
                    }
                    .listRowBackground(Theme.card)
                    .listRowSeparatorTint(Theme.goldEdge)
                }
            }
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
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

/// An upcoming fixture: shield, name, "vs", name, shield — and where and
/// when beneath.
struct FixtureRow: View {
    let match: Match

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Crest(color: match.setup.home.color)
                Text(match.setup.home.name)
                    .font(.headline)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("vs").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                Text(match.setup.away.name)
                    .font(.headline)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Crest(color: match.setup.away.color)
            }
            .foregroundStyle(Theme.ink)
            HStack(spacing: 14) {
                if let competition = match.setup.competition, !competition.isEmpty {
                    Label(competition, systemImage: "mappin.and.ellipse")
                }
                Label((match.setup.kickOff ?? match.createdAt).formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }
}

/// A played match: names either side of a big gold score, the competition
/// and date under it, and each side's scorers beneath its name.
struct ResultRow: View {
    let match: Match

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(match.setup.home.name)
                    .font(.headline)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(scoreText)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
                    .fixedSize()
                Text(match.setup.away.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.ink)
            if let competition = match.setup.competition, !competition.isEmpty {
                Text(competition).font(.subheadline).foregroundStyle(Theme.ink.opacity(0.85))
            }
            Text((match.setup.kickOff ?? match.createdAt).formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(Theme.muted)
            let home = MatchReport.goals(for: .home, in: match)
            let away = MatchReport.goals(for: .away, in: match)
            if !home.isEmpty || !away.isEmpty {
                HStack(alignment: .top) {
                    Text(home.joined(separator: ", "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(away.joined(separator: ", "))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }

    /// No score where the division keeps none (8U).
    private var scoreText: String {
        match.setup.format?.keepsScore == false ? "vs" : "\(match.score.home) - \(match.score.away)"
    }
}
