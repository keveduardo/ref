import RefKit
import SwiftUI

/// Set a match up: the match type, the teams, the kick-off, the clock and the
/// break. Saving it puts it on the shelf, and from there it travels to the
/// watch.
struct MatchSetupScreen: View {
    let store: PhoneStore

    @Environment(\.dismiss) private var dismiss

    @State private var competition = ""
    /// The preset picked, if any. Picking one fills in its defaults; every
    /// field stays editable afterwards.
    /// The division, in two parts: the age from a short list, then girls or
    /// boys underneath (Kevin, 2026-10-04).
    @State private var age: Int?
    @State private var gender: MatchFormat.Gender = .girls

    private var formatID: String? {
        age.flatMap { MatchFormat.preset(age: $0, gender: gender)?.id }
    }
    @State private var homeID: UUID?
    @State private var awayID: UUID?
    @State private var newHome = ""
    @State private var newAway = ""
    /// Each side's number, coach and colour (Kevin, 2026-11-06: "the team
    /// section should have an area for team number, coach name, and color").
    /// Filled from a saved team when one is picked; changes here are this
    /// match's.
    @State private var home = TeamDraft(color: Team.placeholder(.home).color)
    @State private var away = TeamDraft(color: Team.placeholder(.away).color)

    struct TeamDraft {
        var number = ""
        var coach = ""
        var color: TeamColor
    }
    @State private var hasKickOff = true
    @State private var kickOff = Date()
    // Count down by default (Kevin, 2026-10-04); one switch to turn off.
    @State private var countsDown = true
    // This match's own values, starting from the defaults in Settings —
    // changing them here changes this match, not the defaults.
    @State private var halfMinutes: Int
    @State private var halfTimeMinutes: Int
    @State private var addedTimeButton: Bool
    @State private var quarterBreak: QuarterBreak? = QuarterBreakDefaults.value
    @State private var cr = ""
    @State private var ar1 = ""
    @State private var ar2 = ""

    init(store: PhoneStore) {
        self.store = store
        let defaults = UserDefaults.standard
        let half = defaults.integer(forKey: "ref.halfMinutes")
        let rest = defaults.integer(forKey: "ref.halfTimeMinutes")
        _halfMinutes = State(initialValue: half == 0 ? MatchDefaults.standard.halfMinutes : half)
        _halfTimeMinutes = State(initialValue: rest == 0 ? MatchDefaults.standard.halfTimeMinutes : rest)
        _addedTimeButton = State(initialValue: defaults.bool(forKey: "ref.addedTimeButton"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Match type", selection: $age) {
                        Text("Custom").tag(Int?.none)
                        ForEach(MatchFormat.ages, id: \.self) { age in
                            Text(MatchFormat.ageTitle(age)).tag(Optional(age))
                        }
                    }
                    if age != nil {
                        Picker("Girls or boys", selection: $gender) {
                            ForEach(MatchFormat.Gender.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Match type")
                } footer: {
                    if let format = MatchFormat.preset(id: formatID) {
                        Text("\(format.reminder). From AYSO Region 34's local rules (2024 Fall) — change anything below for this match.")
                    }
                }
                .onChange(of: formatID) { old, new in apply(from: old, to: new) }
                Section("Competition") {
                    TextField("Friendly, League…", text: $competition)
                }
                Section("Home team") {
                    teamPicker("Home", selection: $homeID, newName: $newHome, draft: $home)
                }
                Section("Away team") {
                    teamPicker("Away", selection: $awayID, newName: $newAway, draft: $away)
                }
                Section("Kick-off") {
                    Toggle("Set a time", isOn: $hasKickOff)
                    if hasKickOff {
                        DatePicker("Kick-off", selection: $kickOff,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Picker("Half length", selection: $halfMinutes) {
                        ForEach(halfLengths, id: \.self) { Text("\($0) minutes") }
                    }
                    Picker("Half-time", selection: $halfTimeMinutes) {
                        ForEach(halfTimeLengths, id: \.self) { Text("\($0) minutes") }
                    }
                    Toggle("Count down", isOn: $countsDown)
                    Toggle("Added time button", isOn: $addedTimeButton)
                } header: {
                    Text("Clock")
                } footer: {
                    Text("The watch buzzes when half-time is up. The added time button puts \u{201C}+1 min\u{201D} on the watch for announcing stoppage time.")
                }
                QuarterBreakSection(quarterBreak: $quarterBreak, halfMinutes: halfMinutes)
                Section("Referees") {
                    TextField("Center referee", text: $cr).textContentType(.name)
                    TextField("AR1 name", text: $ar1).textContentType(.name)
                    TextField("AR2 name", text: $ar2).textContentType(.name)
                }
            }
            .themedBackground()
            .navigationTitle("New match")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Top right, always in reach however far the form scrolls
                // (Kevin, 2026-10-04) — it used to sit at the bottom.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(homeTeam.id == awayTeam.id)
                }
            }
        }
    }

    private let halfLengths = [20, 25, 30, 35, 40, 45]
    private let halfTimeLengths = Array(1...15)

    // MARK: - Team resolution

    private var homeTeam: Team { resolve(homeID, newHome, home, .home) }
    private var awayTeam: Team { resolve(awayID, newAway, away, .away) }

    /// A team left blank is a placeholder ("Home", blue / "Away", red) — a
    /// match can be made in two taps and named on the Edit screen later.
    private func resolve(_ id: UUID?, _ typed: String, _ draft: TeamDraft, _ side: TeamSide) -> Team {
        var team: Team
        if let id, let squad = store.squads.first(where: { $0.team.id == id }) {
            team = squad.team
        } else {
            let name = typed.trimmingCharacters(in: .whitespaces)
            team = name.isEmpty ? .placeholder(side) : Team(name: name)
        }
        let number = draft.number.trimmingCharacters(in: .whitespaces)
        let coach = draft.coach.trimmingCharacters(in: .whitespaces)
        team.number = number.isEmpty ? nil : number
        team.coach = coach.isEmpty ? nil : coach
        team.color = draft.color
        return team
    }

    @ViewBuilder
    private func teamPicker(_ label: String, selection: Binding<UUID?>,
                            newName: Binding<String>, draft: Binding<TeamDraft>) -> some View {
        Picker("Team", selection: selection) {
            Text("New team…").tag(UUID?.none)
            ForEach(store.squads, id: \.team.id) { squad in
                Text(squad.team.name).tag(Optional(squad.team.id))
            }
        }
        .onChange(of: selection.wrappedValue) { _, id in
            // A saved team brings its own number, coach and colour.
            guard let id, let team = store.squads.first(where: { $0.team.id == id })?.team else { return }
            draft.wrappedValue = TeamDraft(number: team.number ?? "", coach: team.coach ?? "", color: team.color)
        }
        if selection.wrappedValue == nil {
            TextField("\(label) team name (optional)", text: newName)
        }
        TextField("Team number", text: draft.number)
        TextField("Coach", text: draft.coach).textContentType(.name)
        TeamColorPicker(color: draft.color)
    }

    private func save() {
        store.createMatch(
            home: homeTeam, away: awayTeam,
            competition: competition.trimmingCharacters(in: .whitespaces).isEmpty ? nil : competition,
            kickOff: hasKickOff ? kickOff : nil,
            clock: ClockConfig(halfMinutes: halfMinutes, countsDown: countsDown),
            halfTimeMinutes: halfTimeMinutes,
            addedTimeButton: addedTimeButton,
            formatID: formatID,
            quarterBreak: quarterBreak,
            cr: cr.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cr.trimmingCharacters(in: .whitespaces),
            ar1: ar1.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ar1.trimmingCharacters(in: .whitespaces),
            ar2: ar2.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ar2.trimmingCharacters(in: .whitespaces))
        dismiss()
    }

    /// A preset's defaults, filled in. The competition line takes the
    /// division's name only when the referee has not typed their own (it is
    /// empty, or still the previous preset's name).
    private func apply(from old: String?, to new: String?) {
        guard let format = MatchFormat.preset(id: new) else { return }
        halfMinutes = format.halfMinutes
        // The rules allow a range; the shortest is the referee's usual call.
        halfTimeMinutes = format.halfTimeMinutes.lowerBound
        // Subs at quarters means a quarter break; free subs means none.
        quarterBreak = format.quarterSubstitutions
            ? QuarterBreak(breakMinutes: QuarterBreakDefaults.breakMinutes) : nil
        let typed = competition.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty || typed == MatchFormat.preset(id: old)?.title {
            competition = format.title
        }
    }
}
