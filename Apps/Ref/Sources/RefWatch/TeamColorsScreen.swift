import RefKit
import SwiftUI

/// Each team's colour, from the watch — tap the team names on the clock
/// (Kevin, 2026-11-12: "once the game is going, I can edit the home and away
/// team colors"). A tap chooses; the phone hears of it.
struct TeamColorsScreen: View {
    let session: MatchSession
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let setup = session.match?.setup {
                    side(.home, setup.home)
                    side(.away, setup.away)
                }
                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
        }
    }

    private func side(_ side: TeamSide, _ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(side == .home ? "Home" : "Away") · \(team.abbreviation)")
                .font(.footnote.bold())
                .foregroundStyle(team.color.watchColor)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(TeamColor.allCases, id: \.self) { color in
                    Button {
                        Haptics.play(.click)
                        session.setColor(color, for: side)
                    } label: {
                        Circle()
                            .fill(color.swatchColor)
                            .overlay(Circle().strokeBorder(.gray, lineWidth: 1))
                            .overlay {
                                if team.color == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(color == .white || color == .yellow ? .black : .white)
                                }
                            }
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue.capitalized)
                }
            }
        }
    }
}

extension TeamColor {
    /// The swatch itself: black is black here, where `watchColor` makes it
    /// readable as text on the black face.
    var swatchColor: Color { self == .black ? .black : watchColor }
}
