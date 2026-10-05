import RefKit
import SwiftUI

/// RefTime's look (Kevin's mock-ups, 2026-10-04): deep navy, gold accents,
/// cards with a fine gold edge, uppercase section titles, a crest over each
/// screen. Always dark — set once at the root.
enum Theme {
    static let navy = Color(red: 0.055, green: 0.094, blue: 0.157)
    static let card = Color(red: 0.086, green: 0.137, blue: 0.220)
    static let gold = Color(red: 0.851, green: 0.706, blue: 0.443)
    static let goldEdge = Color(red: 0.851, green: 0.706, blue: 0.443).opacity(0.55)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.62)
}

/// A card: navy-blue fill, rounded, a hairline gold edge.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.goldEdge, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// The navy behind a whole screen, lists and forms included.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.navy.ignoresSafeArea())
    }
}

/// The crest and title over a screen: "MATCHES", "STATISTICS".
struct ScreenHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.gold, Theme.card)
            Text(title.uppercased())
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .tracking(1.5)
                .foregroundStyle(Theme.gold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// An uppercase section title with its symbol: "UPCOMING FIXTURES".
struct SectionTitle: View {
    let symbol: String
    let title: String

    var body: some View {
        Label {
            Text(title.uppercased())
                .font(.headline.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.gold)
        }
    }
}

/// A team's shield in its colour, edged in gold.
struct Crest: View {
    let color: TeamColor
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .resizable().scaledToFit()
                .foregroundStyle(color.crestFill)
            Image(systemName: "shield")
                .resizable().scaledToFit()
                .foregroundStyle(Theme.gold)
        }
        .frame(width: size, height: size)
    }
}

extension TeamColor {
    /// Fills on navy: black is lifted to charcoal so it still reads.
    var crestFill: Color {
        switch self {
        case .black: Color(white: 0.16)
        case .white: Color(white: 0.95)
        default: phoneColor
        }
    }
}
