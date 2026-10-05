import RefKit
import SwiftUI

/// Two taps to a card, three to a substitution — the whole point of the app.
/// And three to take any of it back: Record → Undo → confirm.
///
/// Numbers first, roster second: on the pitch the referee has a shirt in front
/// of them, not a team sheet. When a squad is loaded the numbers it owns are
/// offered (with names attached to the event); without one, 1–18 are offered
/// and the number alone is recorded.
struct RecordFlow: View {
    let session: MatchSession
    /// Set on the swipe pages (home to the right of the live face, away to
    /// the left): the team is already chosen, so a card is two taps.
    var side: TeamSide? = nil
    /// What "done" means on a swipe page — back to the live face. Without it
    /// the flow is a sheet, and done dismisses it.
    var onDone: (@MainActor () -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .menu

    enum RecordKind: String, CaseIterable {
        case goal, yellow, red, substitution

        var title: String {
            switch self {
            case .goal: "Goal"
            case .yellow: "Yellow"
            case .red: "Red"
            case .substitution: "Sub"
            }
        }

        var symbol: String {
            switch self {
            case .goal: "soccerball"
            case .yellow: "rectangle.portrait.fill"
            case .red: "rectangle.portrait.fill"
            case .substitution: "arrow.left.arrow.right"
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
        case undo(MatchEvent, text: String)
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
        case .undo(let event, let text):
            undoStep(event, text)
        }
    }

    // MARK: - Steps

    private var menu: some View {
        ScrollView {
            pageHeader
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                      spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    Button {
                        if let side {
                            step = kind == .substitution ? .off(side) : .player(kind, side)
                        } else {
                            step = .team(kind)
                        }
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
                // The grid's fifth cell — on screen without scrolling.
                if let last = session.lastUndoable {
                    Button {
                        step = .undo(last.event, text: last.text)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Undo")
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if side == nil {
                Button("Cancel") { dismiss() }
                    .font(.footnote)
                    .padding(.top, 4)
            }
        }
    }

    /// The team a swipe page records for, in its colour, above the grid.
    @ViewBuilder
    private var pageHeader: some View {
        if let side, let team = session.match?.setup.team(side) {
            Text(team.name)
                .font(.headline)
                .foregroundStyle(team.color.watchColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// What can be recorded: everything, less the cards in a division that
    /// shows none (Region 34: 7U, 8U and 10U).
    private var kinds: [RecordKind] {
        guard session.match?.setup.format?.showsCards == false else { return RecordKind.allCases }
        return RecordKind.allCases.filter { $0 != .yellow && $0 != .red }
    }

    private func finish() {
        step = .menu
        if let onDone { onDone() } else { dismiss() }
    }

    /// The confirmation names the line exactly as the report would, so the
    /// referee takes back the incident they meant and no other.
    private func undoStep(_ event: MatchEvent, _ text: String) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Take this back?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.body.bold())
                    .multilineTextAlignment(.center)
                Button("Undo", role: .destructive) {
                    session.undo(event)
                    Haptics.play(.directionDown)
                    finish()
                }
                Button("Keep it") { step = .menu }
                    .font(.footnote)
            }
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
            title: "\(kind.title) · \(abbreviation(side))"
        ) { ref in
            switch kind {
            case .goal:
                let scorer = (ref.number > 0 || ref.id != nil) ? ref : nil
                session.goal(side: side, scorer: scorer)
            case .yellow:
                session.card(.yellow, side: side, player: ref)
            case .red:
                session.card(.red, side: side, player: ref)
            case .substitution:
                break // never reaches here
            }
            Haptics.recorded()
            finish()
        }
    }

    private func offStep(_ side: TeamSide) -> some View {
        PlayerPicker(
            squad: session.match?.setup.squad(for: side),
            allowNone: false,
            title: "Off · \(abbreviation(side))"
        ) { off in
            step = .on(side, off: off)
        }
    }

    private func onStep(_ side: TeamSide, _ off: PlayerRef) -> some View {
        PlayerPicker(
            squad: session.match?.setup.squad(for: side),
            allowNone: false,
            title: "On · \(abbreviation(side))"
        ) { on in
            session.substitution(side: side, off: off, on: on)
            Haptics.recorded()
            finish()
        }
    }

    // MARK: - Bits

    /// ! `@escaping` because the Buttons store it, and `@MainActor` because
    /// the call sites form it in a main-actor context — a non-Sendable
    /// closure keeps that isolation, and Swift 6 makes both halves explicit.
    private func teamButtons(_ pick: @escaping @MainActor (TeamSide) -> Void) -> some View {
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

/// The shirt number, on a keypad that fits one screen (Kevin, 2026-10-04:
/// the old grid of 1–18 scrolled): 1–9, ⌫ 0 ✓, the number big at the top,
/// and the player's name under it when a team sheet knows the number. Two
/// digits at most. For a goal, ✓ with nothing typed records no scorer.
struct PlayerPicker: View {
    let squad: Squad?
    let allowNone: Bool
    let title: String
    /// ! `@MainActor`, not a bare closure type: the call sites build this
    /// closure in a `@MainActor` context (the whole View is), and in Swift 6
    /// a non-Sendable closure keeps that isolation — handing it to a
    /// non-isolated parameter is an error, not a warning.
    let pick: @MainActor (PlayerRef) -> Void

    @State private var digits = ""

    private var number: Int { Int(digits) ?? 0 }

    /// The team sheet's player for the number typed, if there is one.
    private var player: Player? {
        guard number > 0 else { return nil }
        return squad?.players.first { $0.number == number }
    }

    private var canSave: Bool { number > 0 || allowNone }

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(number > 0 ? "#\(number)" : (allowNone ? "—" : "#"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            if let player {
                Text(player.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(1...3, id: \.self) { column in
                            digitKey(row * 3 + column)
                        }
                    }
                }
                GridRow {
                    key {
                        Image(systemName: "delete.left")
                    } action: {
                        if !digits.isEmpty { digits.removeLast() }
                    }
                    .disabled(digits.isEmpty)
                    digitKey(0)
                    key {
                        Image(systemName: "checkmark").fontWeight(.bold)
                    } action: {
                        pick(ref())
                    }
                    .tint(.green)
                    .disabled(!canSave)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func digitKey(_ digit: Int) -> some View {
        key {
            Text("\(digit)").font(.system(size: 20, weight: .semibold, design: .rounded))
        } action: {
            if digits.count < 2 { digits.append(String(digit)) }
        }
    }

    /// A key that grows to fill its share of the screen, so the pad never
    /// needs a scroll on any watch size.
    private func key<Label: View>(@ViewBuilder label: () -> Label,
                                  action: @escaping @MainActor () -> Void) -> some View {
        Button {
            Haptics.play(.click)
            action()
        } label: {
            label().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
    }

    private func ref() -> PlayerRef {
        guard number > 0 else { return PlayerRef() }
        if let player { return PlayerRef(player) }
        return PlayerRef(number: number)
    }
}
