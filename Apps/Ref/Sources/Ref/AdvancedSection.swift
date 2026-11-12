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
