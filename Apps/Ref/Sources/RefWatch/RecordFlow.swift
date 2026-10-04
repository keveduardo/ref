import RefKit
import SwiftUI

/// Two taps to a card, three to a substitution — the whole point of the app.
///
/// Numbers first, roster second: on the pitch the referee has a shirt in front
/// of them, not a team sheet. When a squad is loaded the numbers it owns are
/// offered (with names attached to the event); without one, 1–18 are offered
/// and the number alone is recorded.
struct RecordFlow: View {
    let session: MatchSession

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .menu

    enum RecordKind: String, CaseIterable {
        case goal, yellow, red, substitution, sinBin

        var title: String {
            switch self {
            case .goal: "Goal"
            case .yellow: "Yellow"
            case .red: "Red"
            case .substitution: "Sub"
            case .sinBin: "Sin bin"
            }
        }

        var symbol: String {
            switch self {
            case .goal: "soccerball"
            case .yellow: "rectangle.portrait.fill"
            case .red: "rectangle.portrait.fill"
            case .substitution: "arrow.left.arrow.right"
            case .sinBin: "timer"
            }
        }

        var tint: Color {
            switch self {
            case .yellow: .yellow
            case .red: .red
            default: .accentColor
            }
        }
    }

    private enum Step: Equatable {
        case menu
        case team(RecordKind)
        case player(RecordKind, TeamSide)
        case off(TeamSide)
        case on(TeamSide, off: PlayerRef)
    }

    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .menu:
            menu
        case .team(let kind):
            teamStep(kind)
        case .player(let kind, let side):
            playerStep(kind, side)
        case .off(let side):
            offStep(side)
        case .on(let side, let off):
            onStep(side, off)
        }
    }

    // MARK: - Steps

    private var menu: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                      spacing: 6) {
                ForEach(RecordKind.allCases, id: \.self) { kind in
                    Button {
                        step = .team(kind)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(kind.tint)
                            Text(kind.title)
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Button("Cancel") { dismiss() }
                .font(.footnote)
                .padding(.top, 4)
        }
    }

    private func teamStep(_ kind: RecordKind) -> some View {
        VStack(spacing: 8) {
            Text("\(kind.title) — which team?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            teamButtons { side in
                switch kind {
                case .substitution:
                    step = .off(side)
                default:
                    step = .player(kind, side)
                }
            }
        }
    }

    private func playerStep(_ kind: RecordKind, _ side: TeamSide) -> some View {
        PlayerPicker(
            squad: session.match?.setup.squad(for: side),
            allowNone: kind == .goal,
            title: "\(kind.title) — \(abbreviation(side)) number"
        ) { ref in
            switch kind {
            case .goal:
                let scorer = (ref.number > 0 || ref.id != nil) ? ref : nil
                session.goal(side: side, scorer: scorer)
            case .yellow:
                session.card(.yellow, side: side, player: ref)
            case .red:
                session.card(.red, side: side, player: ref)
            case .sinBin:
                session.sinBin(side: side, player: ref)
            case .substitution:
                break // never reaches here
            }
            Haptics.recorded()
            dismiss()
        }
    }

    private func offStep(_ side: TeamSide) -> some View {
        PlayerPicker(
            squad: session.match?.setup.squad(for: side),
            allowNone: false,
            title: "Sub — \(abbreviation(side)) number coming off"
        ) { off in
            step = .on(side, off: off)
        }
    }

    private func onStep(_ side: TeamSide, off: PlayerRef) -> some View {
        PlayerPicker(
            squad: session.match?.setup.squad(for: side),
            allowNone: false,
            title: "Sub — number coming on"
        ) { on in
            session.substitution(side: side, off: off, on: on)
            Haptics.recorded()
            dismiss()
        }
    }

    // MARK: - Bits

    private func teamButtons(_ pick: @escaping (TeamSide) -> Void) -> some View {
        VStack(spacing: 6) {
            ForEach(TeamSide.allCases, id: \.self) { side in
                if let team = session.match?.setup.team(side) {
                    Button {
                        Haptics.play(.click)
                        pick(side)
                    } label: {
                        HStack {
                            Circle()
                                .fill(team.color.watchColor)
                                .frame(width: 10, height: 10)
                            Text(team.abbreviation)
                                .font(.body.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func abbreviation(_ side: TeamSide) -> String {
        session.match?.setup.team(side).abbreviation ?? "—"
    }
}

/// The number grid. A squad's own numbers when there is one, 1–18 when there
/// is not — every number a referee normally needs, in two taps.
struct PlayerPicker: View {
    let squad: Squad?
    let allowNone: Bool
    let title: String
    let pick: (PlayerRef) -> Void

    private var numbers: [Int] {
        if let squad, !squad.players.isEmpty {
            return squad.players.map(\.number).filter { $0 > 0 }.sorted()
        }
        return Array(1...18)
    }

    var body: some View {
        ScrollView {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                      spacing: 4) {
                if allowNone {
                    Button("—") {
                        Haptics.play(.click)
                        pick(PlayerRef())
                    }
                }
                ForEach(numbers, id: \.self) { number in
                    Button("\(number)") {
                        Haptics.play(.click)
                        pick(ref(for: number))
                    }
                }
            }
        }
    }

    private func ref(for number: Int) -> PlayerRef {
        if let player = squad?.players.first(where: { $0.number == number }) {
            return PlayerRef(player)
        }
        return PlayerRef(number: number)
    }
}
