import RefKit
import SwiftUI

/// The phone's home: the shelf of matches, a new one, the season, the
/// settings. Set a match up here, record it on the watch, read it back here.
///
/// The tabs (Kevin, 2026-11-12): + sits beside Matches and opens New match
/// at once; Teams, rarely used, moved into Settings; the corner + and
/// "Paste reminder email" went — the CGI schedule brings the games now.
struct RefScreen: View {
    let store: PhoneStore
    let link: PhoneLink
    let account: AccountStore
    let schedule: ScheduleSync

    @Environment(\.scenePhase) private var scenePhase
    @State private var linkMessage: String?
    @State private var tab = HomeTab.matches
    @State private var addingMatch = false

    enum HomeTab: Hashable { case matches, add, stats, settings }

    @AppStorage("ref.halfMinutes") private var halfMinutes = MatchDefaults.standard.halfMinutes
    @AppStorage("ref.halfTimeMinutes") private var halfTimeMinutes = MatchDefaults.standard.halfTimeMinutes
    @AppStorage("ref.addedTimeButton") private var addedTimeButton = false
    @AppStorage("ref.quarterBreak") private var quarterBreak = false
    @AppStorage("ref.quarterBreakMinutes") private var quarterBreakMinutes = 2

    var body: some View {
        // + is a button dressed as a tab: choosing it opens New match and
        // leaves the tab where it was.
        TabView(selection: Binding(get: { tab },
                                   set: { if $0 == .add { addingMatch = true } else { tab = $0 } })) {
            MatchesScreen(store: store)
                .tabItem { Label("Matches", systemImage: "soccerball") }
                .tag(HomeTab.matches)
            Color.clear
                .tabItem { Label("New", systemImage: "plus.circle.fill") }
                .tag(HomeTab.add)
            StatsScreen(store: store)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(HomeTab.stats)
            SettingsScreen(link: link, account: account, store: store, schedule: schedule)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(HomeTab.settings)
        }
        .sheet(isPresented: $addingMatch) {
            MatchSetupScreen(store: store)
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
        .onChange(of: (store.onWatch + store.upcoming).map(\.setup)) { _, _ in pushAssignment() }
        .onChange(of: halfMinutes) { _, _ in pushAssignment() }
        .onChange(of: halfTimeMinutes) { _, _ in pushAssignment() }
        .onChange(of: addedTimeButton) { _, _ in pushAssignment() }
        // Back in the foreground: pick up what changed on another phone.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await account.sync() }
            Task { await schedule.checkIfDue(store) }
        }
        // reftime://schedule?link=<the My Schedule address>, tapped once,
        // connects the schedule (Kevin, 2026-11-06: "auto add the link").
        .onOpenURL { url in
            guard url.scheme == "reftime", url.host == "schedule",
                  let given = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "link" })?.value else { return }
            if schedule.connect(given) {
                linkMessage = "Your CGI Sports schedule is connected. Its games are on their way to Matches."
                Task { await schedule.check(store) }
            } else {
                linkMessage = "That link isn't a CGI Sports referee schedule."
            }
        }
        .alert("Referee schedule", isPresented: Binding(get: { linkMessage != nil },
                                                        set: { if !$0 { linkMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkMessage ?? "")
        }
        .onChange(of: quarterBreak) { _, _ in pushAssignment() }
        .onChange(of: quarterBreakMinutes) { _, _ in pushAssignment() }
    }

    /// The watch always has the newest set of matches to offer — and the
    /// one it is running, so edits made here to a quick start reach it. (Left
    /// out from 2026-10-04 to 2026-11-12, when "On the watch" was split from
    /// Upcoming: until then a quick start's names and colours stayed on the
    /// phone.) The watch never offers its match in hand back as a choice.
    private func pushAssignment() {
        link.sendAssignment((store.onWatch + store.upcoming).map(\.setup),
                            defaults: MatchDefaults(halfMinutes: halfMinutes,
                                                    halfTimeMinutes: halfTimeMinutes,
                                                    addedTimeButton: addedTimeButton,
                                                    quarterBreak: quarterBreak
                                                        ? QuarterBreak(breakMinutes: quarterBreakMinutes) : nil))
    }
}

struct MatchesScreen: View {
    let store: PhoneStore
    /// The match just deleted by a swipe, kept for a few seconds so a full
    /// swipe by accident can be taken back.
    @State private var recentlyDeleted: Match?

    var body: some View {
        NavigationStack {
            List {
                ScreenHeader(title: "Matches")
                    .bareRow()
                if store.upcoming.isEmpty && store.played.isEmpty && store.onWatch.isEmpty && store.notRefereed.isEmpty {
                    ContentUnavailableView(
                        "No matches yet", systemImage: "soccerball",
                        description: Text("Tap + to set one up, or quick start on the watch."))
                        .bareRow()
                }
                matchCard(symbol: "applewatch", title: "On the watch", matches: store.onWatch,
                          note: "Started on the watch. Tap to name the teams and pick colours.") {
                    FixtureRow(match: $0)
                }
                matchCard(symbol: "megaphone.fill", title: "Upcoming fixtures", matches: store.upcoming) {
                    FixtureRow(match: $0)
                }
                matchCard(symbol: "trophy.fill", title: "Recent results", matches: store.played) {
                    ResultRow(match: $0)
                }
                matchCard(symbol: "calendar.badge.minus", title: "Not refereed", matches: store.notRefereed,
                          note: "Never started, a day past kick-off — off Upcoming and the watch. Swipe to delete.") {
                    FixtureRow(match: $0)
                }
            }
            .listStyle(.plain)
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let match = store.all.first(where: { $0.id == id }) {
                    MatchDetailScreen(store: store, match: match)
                }
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
        }
    }
}

extension MatchesScreen {
    /// A titled card of matches: the title is the card's first row, each
    /// match a row after it — real list rows, so swipe-to-delete still works.
    @ViewBuilder
    fileprivate func matchCard<Row: View>(symbol: String, title: String, matches: [Match],
                                          note: String? = nil,
                                          @ViewBuilder row: @escaping (Match) -> Row) -> some View {
        if !matches.isEmpty {
            let count = matches.count + 1
            Color.clear.frame(height: 6).bareRow()
            SectionTitle(symbol: symbol, title: title)
                .cardRow(RowCard.position(0, of: count))
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                NavigationLink(value: match.id) { row(match) }
                    .modifier(SwipeToDelete { delete(match) })
                    .cardRow(RowCard.position(index + 1, of: count))
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.muted).bareRow()
            }
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
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Crest(color: match.setup.home.color)
                side(match.setup.home.name, "Home", alignment: .trailing)
                Text("vs").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                side(match.setup.away.name, "Away", alignment: .leading)
                Crest(color: match.setup.away.color)
            }
            .foregroundStyle(Theme.ink)
            // Each on its own line, whole (Kevin, 2026-11-12: "for each card
            // you can easily see division and full date and time").
            VStack(spacing: 3) {
                if let competition = match.setup.competition, !competition.isEmpty {
                    Text(competition)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                }
                HStack(spacing: 8) {
                    MatchCardText.roleBadge(match.setup.myRole)
                    Text(MatchCardText.when(match))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    /// A team's name with "HOME" or "AWAY" beneath it.
    private func side(_ name: String, _ label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(name)
                .font(.headline)
                .lineLimit(1).minimumScaleFactor(0.7)
            MatchCardText.sideLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

/// What every match card says the same way.
enum MatchCardText {
    /// "Fri, Nov 13, 2026 · 6:00 PM" — or just the date with no kick-off time.
    static func when(_ match: Match) -> String {
        guard let kickOff = match.setup.kickOff else {
            return match.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
        return "\(kickOff.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())) · \(kickOff.formatted(date: .omitted, time: .shortened))"
    }

    /// The referee's own slot, "CR" or "AR", in gold — nothing when unknown.
    @ViewBuilder static func roleBadge(_ role: RefereeRole?) -> some View {
        if let role {
            Text("You: \(role.rawValue)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.gold, in: Capsule())
                .accessibilityLabel("You are \(role.title.lowercased())")
        }
    }

    static func sideLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.gold.opacity(0.8))
    }
}

/// A played match: names either side of a big gold score, the competition
/// and date under it, and each side's scorers beneath its name.
struct ResultRow: View {
    let match: Match

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(match.setup.home.name)
                        .font(.headline)
                        .multilineTextAlignment(.trailing)
                    MatchCardText.sideLabel("Home")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text(scoreText)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.setup.away.name)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    MatchCardText.sideLabel("Away")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.ink)
            if let competition = match.setup.competition, !competition.isEmpty {
                Text(competition).font(.subheadline).foregroundStyle(Theme.ink.opacity(0.85))
            }
            HStack(spacing: 8) {
                MatchCardText.roleBadge(match.setup.myRole)
                Text(MatchCardText.when(match))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
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

    /// The score in every division, 8U too — as the watch shows it.
    private var scoreText: String { "\(match.score.home) - \(match.score.away)" }
}
