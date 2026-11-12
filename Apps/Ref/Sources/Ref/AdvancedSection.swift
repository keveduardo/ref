import RefKit
import SwiftUI

/// The row that folds a match form's less-used settings away (Kevin,
/// 2026-11-12: "an 'advanced' option that hides these other items"). Closed,
/// it says what is inside, so nothing set there is out of sight entirely.
struct AdvancedToggle: View {
    @Binding var isOpen: Bool
    let summary: String

    var body: some View {
        Section {
            Button {
                withAnimation { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced")
                            .foregroundStyle(Theme.ink)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(Theme.gold)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            if !isOpen {
                Text("Team numbers and coaches, the clock, quarter breaks and the referees' names.")
            }
        }
    }

    /// "25 min halves · 5 min half-time · counts down · quarter breaks · 2 referees".
    static func summary(halfMinutes: Int, halfTimeMinutes: Int, countsDown: Bool,
                        quarterBreak: QuarterBreak?, referees: [String?]) -> String {
        var parts = ["\(halfMinutes) min halves", "\(halfTimeMinutes) min half-time",
                     countsDown ? "counts down" : "counts up"]
        if quarterBreak != nil { parts.append("quarter breaks") }
        let named = referees.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
        if named > 0 { parts.append("\(named) referee\(named == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

/// The referee's own slot, for both match forms.
struct MyRolePicker: View {
    @Binding var role: RefereeRole?

    var body: some View {
        Picker("Your position", selection: $role) {
            Text("Not set").tag(RefereeRole?.none)
            ForEach(RefereeRole.allCases, id: \.self) { role in
                Text(role.title).tag(RefereeRole?.some(role))
            }
        }
    }
}

/// Beach Cup tournament: a toggle, and the round, which with the division's
/// age sets the half length from the tournament's sheet (Kevin, 2026-11-12).
/// In view on both match forms, not under Advanced.
struct BeachCupSection: View {
    @Binding var round: BeachCupRound?
    /// The division's age — 10, 12, 14 are on the sheet.
    let age: Int?
    /// Sets the match's half length.
    let setHalfMinutes: (Int) -> Void

    var body: some View {
        Section {
            Toggle("Beach Cup tournament", isOn: Binding(
                get: { round != nil },
                set: { on in
                    round = on ? (round ?? .pool) : nil
                    apply()
                }))
            if round != nil {
                Picker("Round", selection: Binding(
                    get: { round ?? .pool },
                    set: { round = $0; apply() })) {
                    ForEach(BeachCupRound.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } footer: {
            if let round {
                if let age, let minutes = round.halfMinutes(age: age) {
                    Text("U\(age) \(round.title): \(minutes) min halves, from the tournament's sheet.")
                } else {
                    Text("The tournament's sheet has half lengths for U10, U12 and U14 — choose one of those as the match type, or set the halves under Advanced.")
                }
            }
        }
    }

    private func apply() {
        guard let round, let age, let minutes = round.halfMinutes(age: age) else { return }
        setHalfMinutes(minutes)
    }
}
