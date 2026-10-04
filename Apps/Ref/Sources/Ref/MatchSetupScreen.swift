import RefKit
import SwiftUI

/// Set a match up: the match type, the teams, the clock, the kick-off, the
/// sin bin. Saving it puts it on the shelf, and from there it travels to the
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
    @State private var countsDown = false
    // This match's own values, starting from the defaults in Settings —
    // changing them here changes this match, not the defaults.
    @State private var halfMinutes: Int
    @State private var sinBinMinutes: Int

    init(store: PhoneStore) {
        self.store = store
        let defaults = UserDefaults.standard
        let half = defaults.integer(forKey: "ref.halfMinutes")
        let bin = defaults.integer(forKey: "ref.sinBinMinutes")
        _halfMinutes = State(initialValue: half == 0 ? MatchDefaults.standard.halfMinutes : half)
        _sinBinMinutes = State(initialValue: bin == 0 ? MatchDefaults.standard.sinBinMinutes : bin)
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
                Section("Clock") {
                    Picker("Half length", selection: $halfMinutes) {
                        ForEach(halfLengths, id: \.self) { Text("\($0) minutes") }
                    }
                    Toggle("Count down", isOn: $countsDown)
                }
                Section {
                    Picker("Sin bin", selection: $sinBinMinutes) {
                        ForEach([5, 10, 15], id: \.self) { Text("\($0) minutes") }
                    }
                } header: {
                    Text("Sin bins")
                } footer: {
                    Text("The watch runs this countdown, and buzzes when the player may return.")
                }
                Section {
                    Button("Save match") { save() }
                        .disabled(homeTeam == nil || awayTeam == nil || homeTeam?.id == awayTeam?.id)
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

    // MARK: - Team resolution

    private var homeTeam: Team? { resolve(homeID, newHome) }
    private var awayTeam: Team? { resolve(awayID, newAway) }

    private func resolve(_ id: UUID?, _ typed: String) -> Team? {
        if let id, let squad = store.squads.first(where: { $0.team.id == id }) {
            return squad.team
        }
        let name = typed.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : Team(name: name)
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
            TextField("\(label) team name", text: newName)
        }
    }

    private func save() {
        guard let home = homeTeam, let away = awayTeam else { return }
        store.createMatch(
            home: home, away: away,
            competition: competition.trimmingCharacters(in: .whitespaces).isEmpty ? nil : competition,
            kickOff: hasKickOff ? kickOff : nil,
            clock: ClockConfig(halfMinutes: halfMinutes, countsDown: countsDown),
            sinBinMinutes: sinBinMinutes,
            formatID: formatID)
        dismiss()
    }

    /// A preset's defaults, filled in. The competition line takes the
    /// division's name only when the referee has not typed their own (it is
    /// empty, or still the previous preset's name).
    private func apply(from old: String?, to new: String?) {
        guard let format = MatchFormat.preset(id: new) else { return }
        halfMinutes = format.halfMinutes
        let typed = competition.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty || typed == MatchFormat.preset(id: old)?.title {
            competition = format.title
        }
    }
}
