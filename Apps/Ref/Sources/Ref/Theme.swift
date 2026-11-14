import RefKit
import SwiftUI

/// RefTime's look. Navy and gold from Kevin's first mock-ups (2026-10-04);
/// since 2026-11-14 his second: dark slate, a cyan edge that glows, lime for
/// the score and the assistant's badge. Always dark — set once at the root.
enum Theme {
    /// Behind every screen.
    static let background = Color(red: 0.118, green: 0.161, blue: 0.188)
    /// A card's fill, a step lighter than the background.
    static let card = Color(red: 0.145, green: 0.200, blue: 0.235)
    /// One game's own box inside a card.
    static let inset = Color(red: 0.165, green: 0.227, blue: 0.267)
    /// What is selected, titles' symbols, "vs", HOME/AWAY.
    static let accent = Color(red: 0.239, green: 0.698, blue: 0.961)
    /// The score, and the assistant referee's badge.
    static let lime = Color(red: 0.655, green: 0.933, blue: 0.180)
    static let edge = accent.opacity(0.6)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.62)
}

/// A card: slate fill, rounded, a fine cyan edge with a soft glow.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.edge, lineWidth: 1))
            .shadow(color: Theme.accent.opacity(0.25), radius: 8)
    }
}

/// One game's own box inside a card (the 2026-11-14 mock-up): a lighter
/// fill and a cyan hairline.
struct InsetBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.edge.opacity(0.7), lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
    func insetBox() -> some View { modifier(InsetBox()) }

    /// The slate behind a whole screen, lists and forms included.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

/// The crest over a screen, and its title when it has one ("STATISTICS").
/// Matches has none (Kevin, 2026-11-14: the tab already says it).
struct ScreenHeader: View {
    var title: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.lime],
                                                startPoint: .topLeading, endPoint: .bottomTrailing),
                                 Theme.card)
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 28, weight: .heavy, design: .rounded).italic())
                    .tracking(1)
                    .foregroundStyle(LinearGradient(colors: [Theme.ink, Theme.lime],
                                                    startPoint: .leading, endPoint: .trailing))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// An uppercase section title with its symbol: "UPCOMING FIXTURES".
struct SectionTitle: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.accent

    var body: some View {
        Label {
            Text(title.uppercased())
                .font(.headline.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

/// A team's shield in its colour, lit from above, edged a shade lighter.
struct Crest: View {
    let color: TeamColor
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .resizable().scaledToFit()
                .foregroundStyle(color.crestFill.gradient)
            Image(systemName: "shield")
                .resizable().scaledToFit()
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(width: size, height: size)
    }
}

extension TeamColor {
    /// Fills on slate: black is lifted to charcoal so it still reads.
    var crestFill: Color {
        switch self {
        case .black: Color(white: 0.16)
        case .white: Color(white: 0.95)
        default: phoneColor
        }
    }
}

/// One row's slice of a card, for lists — where swipe-to-delete needs real
/// list rows, so a section cannot simply be wrapped in `.card()`. Each row
/// draws the card shape stretched past its own edges and clipped to itself:
/// the first row shows the rounded top and gold top edge, middle rows the
/// gold sides, the last the rounded bottom. A hairline gold rule divides
/// rows. Pair with `cardRow(_:)`.
struct RowCard: View {
    enum Position { case only, first, middle, last }
    let position: Position

    var body: some View {
        GeometryReader { geometry in
            let stretchTop: CGFloat = (position == .middle || position == .last) ? 40 : 0
            let stretchBottom: CGFloat = (position == .middle || position == .first) ? 40 : 0
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                shape.fill(Theme.card)
                shape.strokeBorder(Theme.edge, lineWidth: 1)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height + stretchTop + stretchBottom)
            .offset(y: -stretchTop)
        }
        .clipped()
        .padding(.horizontal, 16)
    }

    /// Where row `index` of `count` sits in its card.
    static func position(_ index: Int, of count: Int) -> Position {
        if count <= 1 { return .only }
        if index == 0 { return .first }
        return index == count - 1 ? .last : .middle
    }
}

extension View {
    /// A list row drawn as its slice of a card (plain list style).
    func cardRow(_ position: RowCard.Position) -> some View {
        listRowBackground(RowCard(position: position))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 32, bottom: 10, trailing: 32))
    }

    /// A list row with nothing behind it: headers, gaps, notes.
    func bareRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}
