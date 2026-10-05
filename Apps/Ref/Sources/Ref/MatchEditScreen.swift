import RefKit
import SwiftUI

/// Change an upcoming match: who is home and away, their names, short names
/// and colours, and the clock. The edit is saved to the shelf, and the shelf
/// sends it on to the watch — until the match is started there, after which
/// the watch's own copy is the match.
struct MatchEditScreen: View {
    let store: PhoneStore
    let match: Match

    @Environment(\.dismiss) private var dismiss
    @State private var setup: MatchSetup
    @State private var hasKickOff: Bool
    @State private var kickOff: Date

    init(store: PhoneStore, match: Match) {
        self.store = store
        self.match = match
        _setup = State(initialValue: match.setup)
        _hasKickOff = State(initialValue: match.setup.kickOff != nil)
        _kickOff = State(initialValue: match.setup.kickOff ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                teamSection("Home", team: $setup.home)
                teamSection("Away", team: $setup.away)
                Section {
                    Button {
                        setup = setup.swappingSides()
                    } label: {
                        Label("Swap home and away", systemImage: "arrow.up.arrow.down")
                    }
                }
                Section("Assistant referees") {
                    TextField("AR1 name", text: optionalText($setup.ar1))
                    TextField("AR2 name", text: optionalText($setup.ar2))
                }
                Section("Competition") {
                    TextField("Friendly, League…", text: Binding(
                        get: { setup.competition ?? "" },
                        set: { setup.competition = $0.isEmpty ? nil : $0 }))
                }
                Section("Kick-off") {
                    Toggle("Set a time", isOn: $hasKickOff)
                    if hasKickOff {
                        DatePicker("Kick-off", selection: $kickOff,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Picker("Half length", selection: halfMinutes) {
                        ForEach([20, 25, 30, 35, 40, 45], id: \.self) { Text("\($0) minutes") }
                    }
                    Picker("Half-time", selection: $setup.halfTimeMinutes) {
                        ForEach(1...15, id: \.self) { Text("\($0) minutes") }
                    }
                    Toggle("Count down", isOn: $setup.clock.countsDown)
                    Toggle("Added time button", isOn: $setup.addedTimeButton)
                } header: {
                    Text("Clock")
                } footer: {
                    Text("Team names, colours and sheets reach the watch any time, mid-match too. Clock changes reach it only before kick-off.")
                }
                QuarterBreakSection(quarterBreak: $setup.quarterBreak,
                                    halfMinutes: Int(setup.clock.halfLength / 60))
            }
            .themedBackground()
            .navigationTitle("Edit match")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(setup.home.name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || setup.away.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// An optional name as a text field: empty means none.
    private func optionalText(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" },
                set: { value.wrappedValue = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    /// The clock stores seconds; the picker works in minutes.
    private var halfMinutes: Binding<Int> {
        Binding(get: { Int(setup.clock.halfLength / 60) },
                set: { setup.clock.halfLength = TimeInterval($0 * 60) })
    }

    private func teamSection(_ title: String, team: Binding<Team>) -> some View {
        Section(title) {
            TextField("Name", text: team.name)
            TextField("Short (3 letters)", text: Binding(
                get: { team.wrappedValue.abbreviation },
                set: { team.wrappedValue.abbreviation = String($0.uppercased().prefix(3)) }))
            Picker("Colour", selection: team.color) {
                ForEach(TeamColor.allCases, id: \.self) { token in
                    Label {
                        Text(token.rawValue.capitalized)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(token.phoneColor)
                    }
                    .tag(token)
                }
            }
        }
    }

    private func save() {
        var updated = match
        updated.setup = setup
        updated.setup.kickOff = hasKickOff ? kickOff : nil
        // A short name left empty falls back to one made from the name.
        for side in TeamSide.allCases {
            var team = updated.setup.team(side)
            if team.abbreviation.trimmingCharacters(in: .whitespaces).isEmpty {
                team.abbreviation = Team.defaultAbbreviation(team.name)
                if side == .home { updated.setup.home = team } else { updated.setup.away = team }
            }
        }
        store.save(updated)
        dismiss()
    }
}
