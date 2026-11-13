import RefKit
import SwiftUI
import UIKit

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
    @State private var showingAdvanced = false

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
                // Not once the watch has it: goals and cards are recorded by
                // side, and a swap mid-match would move them.
                if !store.startedOnWatch.contains(match.id) && match.events.recorded.isEmpty {
                    Section {
                        Button {
                            setup = setup.swappingSides()
                        } label: {
                            Label("Swap home and away", systemImage: "arrow.up.arrow.down")
                        }
                    }
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
                    MyRolePicker(role: $setup.myRole)
                }
                BeachCupSection(round: $setup.beachCup, age: setup.format?.age) {
                    setup.clock.halfLength = TimeInterval($0 * 60)
                }
                AdvancedToggle(isOpen: $showingAdvanced, summary: AdvancedToggle.summary(
                    halfMinutes: Int(setup.clock.halfLength / 60), halfTimeMinutes: setup.halfTimeMinutes,
                    countsDown: setup.clock.countsDown, quarterBreak: setup.quarterBreak,
                    referees: [setup.cr, setup.ar1, setup.ar2]))
                if showingAdvanced {
                    advanced
                }
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

    /// Behind Advanced: the teams' numbers and coaches, the clock, quarter
    /// breaks and the referees' names.
    @ViewBuilder
    private var advanced: some View {
                Section("Team details") {
                    TextField("Home team number", text: optionalText($setup.home.number))
                    TextField("Home coach", text: optionalText($setup.home.coach))
                    TextField("Away team number", text: optionalText($setup.away.number))
                    TextField("Away coach", text: optionalText($setup.away.coach))
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
                Section("Referees") {
                    TextField("Center referee", text: optionalText($setup.cr))
                    TextField("AR1 name", text: optionalText($setup.ar1))
                    TextField("AR2 name", text: optionalText($setup.ar2))
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
            TeamColorPicker(color: team.color)
        }
    }

    private func save() {
        // The store's copy as it is now — a finished match may have arrived
        // from the watch while this screen was open.
        var updated = store.all.first(where: { $0.id == match.id }) ?? match
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

/// A team's colour, each choice with its swatch — on the new match, edit
/// match and team screens alike.
struct TeamColorPicker: View {
    @Binding var color: TeamColor

    var body: some View {
        Picker("Colour", selection: $color) {
            ForEach(TeamColor.allCases, id: \.self) { token in
                Label {
                    Text(token.rawValue.capitalized)
                } icon: {
                    Image(uiImage: token.swatch)
                }
                .tag(token)
            }
        }
    }
}

extension TeamColor {
    /// The swatch as a finished picture. A symbol would be repainted in the
    /// app's gold inside a menu (Kevin, 2026-11-12: "Colors should actually
    /// show"); a drawn image keeps its own colour. The grey ring keeps black
    /// and white visible on either background.
    var swatch: UIImage {
        let fill: UIColor = switch self {
        case .red: .systemRed
        case .blue: .systemBlue
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .black: .black
        case .white: .white
        }
        let size = CGSize(width: 22, height: 22)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let ring = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            fill.setFill()
            ring.fill()
            UIColor.systemGray.setStroke()
            ring.lineWidth = 1
            ring.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
