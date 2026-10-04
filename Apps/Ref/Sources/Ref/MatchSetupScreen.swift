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
    @State private var formatID: String?
    @State private var homeID: UUID?
    @State private var awayID: UUID?
    @State private var newHome = ""
    @State private var newAway = ""
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
                    Picker("Match type", selection: $formatID) {
                        Text("Custom").tag(String?.none)
                        ForEach(MatchFormat.presets) { format in
                            Text(format.title).tag(Optional(format.id))
                        }
                    }
                } header: {
                    Text("Match type")
                } footer: {
                    if let format = MatchFormat.preset(id: formatID) {
                        Text("\(format.reminder). Defaults from the AYSO National Rules & Regulations — change anything below for this match.")
                    }
                }
                .onChange(of: formatID) { old, new in apply(from: old, to: new) }
                Section("Competition") {
                    TextField("Friendly, League…", text: $competition)
                }
                Section("Teams") {
                    teamPicker("Home", selection: $homeID, newName: $newHome)
                    teamPicker("Away", selection: $awayID, newName: $newAway)
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
                Section {
                    Button("Save match") { save() }
                        .disabled(homeTeam.id == awayTeam.id)
                }
            }
            .navigationTitle("New match")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private let halfLengths = [20, 25, 30, 35, 40, 45]
    private let halfTimeLengths = Array(1...15)

    // MARK: - Team resolution

    private var homeTeam: Team { resolve(homeID, newHome, .home) }
    private var awayTeam: Team { resolve(awayID, newAway, .away) }

    /// A team left blank is a placeholder ("Home", blue / "Away", red) — a
    /// match can be made in two taps and named on the Edit screen later.
    private func resolve(_ id: UUID?, _ typed: String, _ side: TeamSide) -> Team {
        if let id, let squad = store.squads.first(where: { $0.team.id == id }) {
            return squad.team
        }
        let name = typed.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? .placeholder(side) : Team(name: name, color: Team.placeholder(side).color)
    }

    @ViewBuilder
    private func teamPicker(_ label: String, selection: Binding<UUID?>,
                            newName: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Text("New team…").tag(UUID?.none)
            ForEach(store.squads, id: \.team.id) { squad in
                Text(squad.team.name).tag(Optional(squad.team.id))
            }
        }
        if selection.wrappedValue == nil {
            TextField("\(label) team name (optional)", text: newName)
        }
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
            quarterBreak: quarterBreak)
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
        let typed = competition.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty || typed == MatchFormat.preset(id: old)?.title {
            competition = format.title
        }
    }
}
