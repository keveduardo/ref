import RefKit
import SwiftUI

/// The season, folded from the finished matches — in the look of Kevin's
/// mock-up: a card each for the season, the referee's own running, and
/// discipline, with the numbers big and gold.
struct StatsScreen: View {
    let store: PhoneStore

    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = store.stats
                VStack(spacing: 18) {
                    ScreenHeader(title: "Statistics")

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(symbol: "chart.bar.fill", title: "Season performance")
                        HStack(alignment: .top) {
                            BigStat(symbol: "sportscourt.fill", title: "Matches Played",
                                    value: "\(stats.matches)", caption: "Matches tracked this season")
                            BigStat(symbol: "soccerball", title: "Goals Seen",
                                    value: "\(stats.goals)", caption: "Across all matches")
                        }
                    }
                    .card()

                    activityCard(stats.activity)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(symbol: "flag.fill", title: "Disciplinary record")
                        HStack(alignment: .top) {
                            CardStat(color: .yellow, title: "Yellow Cards",
                                     value: stats.yellowCards, caption: "Cautions")
                            CardStat(color: .red, title: "Red Cards",
                                     value: stats.redCards, caption: "Sendings-off")
                        }
                        Divider().overlay(Theme.goldEdge)
                        HStack {
                            Image(systemName: "rectangle.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(Theme.gold)
                            Text("Cards per Match")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(String(format: "%.2f", stats.cardsPerMatch))
                                    .font(.system(size: 28, weight: .bold, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                // Full at two cards a match — busy for youth soccer.
                                ProgressView(value: min(stats.cardsPerMatch / 2, 1))
                                    .tint(Theme.gold)
                                    .frame(width: 90)
                            }
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The referee's own season, from each match's health numbers.
    private func activityCard(_ activity: SeasonStats.Activity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(symbol: "figure.run", title: "On the move")
            if activity.isEmpty {
                Text("Distance, steps and heart rate appear here after a match played with Health access on the watch.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    if let perMatch = activity.distancePerMatch {
                        BigStat(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Distance",
                                value: String(format: "%.1f km", activity.distanceMeters / 1000),
                                caption: String(format: "%.1f km per match", perMatch / 1000))
                    }
                    if let perMatch = activity.stepsPerMatch {
                        BigStat(symbol: "shoeprints.fill", title: "Steps",
                                value: activity.steps.formatted(),
                                caption: "\(perMatch.formatted()) per match")
                    }
                    if let average = activity.averageHeartRate {
                        BigStat(symbol: "heart.fill", title: "Heart Rate",
                                value: "\(Int(average))",
                                caption: "avg · \(Int(activity.maxHeartRate ?? 0)) highest")
                    }
                    if activity.activeCalories > 0 {
                        BigStat(symbol: "flame.fill", title: "Active Energy",
                                value: Int(activity.activeCalories).formatted(),
                                caption: "kcal this season")
                    }
                }
            }
        }
        .card()
    }
}

/// A big gold number with its symbol, title and a line beneath.
private struct BigStat: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(Theme.gold)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(value)
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(Theme.gold)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A card count drawn as the card itself.
private struct CardStat: View {
    let color: Color
    let title: String
    let value: Int
    let caption: String

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.gradient)
                .frame(width: 44, height: 60)
                .shadow(color: color.opacity(0.4), radius: 6)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}
