import RefKit
import SwiftUI

/// The teams the referee keeps: names, colours, and the squads the watch
/// offers as numbers.
struct TeamsScreen: View {
    let store: PhoneStore
    @State private var editing: Squad?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if store.squads.isEmpty {
                    ContentUnavailableView(
                        "No teams yet", systemImage: "person.3",
                        description: Text("Add one, with its players, and its numbers appear on the watch."))
                }
                ForEach(store.squads, id: \.team.id) { squad in
                    Button {
                        editing = squad
                    } label: {
                        TeamRow(squad: squad)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Teams")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label("New team", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { squad in
                TeamEditorScreen(store: store, existing: squad)
            }
            .sheet(isPresented: $creating) {
                TeamEditorScreen(store: store, existing: nil)
            }
        }
    }
}

struct TeamRow: View {
    let squad: Squad

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(squad.team.color.phoneColor)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(squad.team.name)
                Text("\(squad.team.abbreviation) · \(squad.players.count) player\(squad.players.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Squad identity comes from RefKit (`Squad.id` is the team's id); this screen
/// only shows it.

struct TeamEditorScreen: View {
    let store: PhoneStore
    let existing: Squad?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var abbreviation: String
    @State private var color: TeamColor
    @State private var players: [Player]
    @State private var newNumber = ""
    @State private var newName = ""
    @State private var confirmingDelete = false

    init(store: PhoneStore, existing: Squad?) {
        self.store = store
        self.existing = existing
        _name = State(initialValue: existing?.team.name ?? "")
        _abbreviation = State(initialValue: existing?.team.abbreviation ?? "")
        _color = State(initialValue: existing?.team.color ?? .blue)
        _players = State(initialValue: existing?.players ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Name", text: $name)
                    TextField("Short (3 letters)", text: $abbreviation)
                    Picker("Colour", selection: $color) {
                        ForEach(TeamColor.allCases, id: \.self) { token in
                            Text(token.rawValue.capitalized).tag(token)
                        }
                    }
                }
                Section("Players") {
                    ForEach(players) { player in
                        HStack(spacing: 10) {
                            Text("#\(player.number)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(player.name)
                        }
                    }
                    .onDelete { players.remove(atOffsets: $0) }
                    HStack(spacing: 8) {
                        TextField("#", text: $newNumber)
                            .keyboardType(.numberPad)
                            .frame(width: 48)
                        TextField("Name", text: $newName)
                        Button("Add") { addPlayer() }
                            .disabled(newNumber.isEmpty && newName.isEmpty)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete team", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New team" : (name.isEmpty ? "Team" : name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this team?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    if let existing {
                        store.deleteTeam(existing)
                    }
                    dismiss()
                }
            }
        }
    }

    private func addPlayer() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let number = Int(newNumber) ?? 0
        players.append(Player(name: trimmed.isEmpty ? "Player \(players.count + 1)" : trimmed,
                              number: number))
        players.sort { $0.number < $1.number }
        newNumber = ""
        newName = ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let short = abbreviation.trimmingCharacters(in: .whitespaces).uppercased()
        let team = Team(id: existing?.team.id ?? UUID(),
                        name: trimmed,
                        abbreviation: short.isEmpty ? nil : short,
                        color: color)
        store.saveTeam(Squad(team: team, players: players))
        dismiss()
    }
}
