import RefKit
import SwiftUI

/// The season, folded from the finished matches.
struct StatsScreen: View {
    let store: PhoneStore

    var body: some View {
        NavigationStack {
            List {
                let stats = store.stats
                Section("Season") {
                    LabeledContent("Matches", value: "\(stats.matches)")
                    LabeledContent("Goals seen", value: "\(stats.goals)")
                }
                Section("Discipline") {
                    LabeledContent("Yellow cards", value: "\(stats.yellowCards)")
                    LabeledContent("Red cards", value: "\(stats.redCards)")
                    LabeledContent("Cards per match", value: String(format: "%.1f", stats.cardsPerMatch))
                }
            }
            .navigationTitle("Stats")
        }
    }
}
