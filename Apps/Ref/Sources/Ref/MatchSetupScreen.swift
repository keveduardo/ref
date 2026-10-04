import RefKit
import SwiftUI

/// Set a match up: the teams, the clock, the kick-off. Saving it puts it on
/// the shelf; it travels to the watch in P4.
struct MatchSetupScreen: View {
    let store: PhoneStore

    @Environment(\.dismiss) private var dismiss

    @State private var competition = ""
    @State private var homeID: UUID?
    @State private var awayID: UUID?
    @State private var newHome = ""
    @State private var newAway = ""
    @State private var hasKickOff = true
    @State private var kickOff = Date()
    @State private var halfMinutes = 45
    @State private var countsDown = false

    @AppStorage("ref.sinBinMinutes") private var sinBinMinutes = 10

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("The watch runs this countdown when you record one.")
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
        // The defaults the watch reads, written where SessionSettings finds
        // them (UserDefaults, mirrored properly in P4).
        UserDefaults.standard.set(halfMinutes, forKey: "ref.halfMinutes")
        store.createMatch(
            home: home, away: away,
            competition: competition.trimmingCharacters(in: .whitespaces).isEmpty ? nil : competition,
            kickOff: hasKickOff ? kickOff : nil,
            clock: ClockConfig(halfMinutes: halfMinutes, countsDown: countsDown))
        dismiss()
    }
}
