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
                // The referee's own season, from each match's health numbers.
                Section {
                    let activity = stats.activity
                    if activity.isEmpty {
                        Text("Distance, steps and heart rate appear here after a match played with Health access on the watch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        if let perMatch = activity.distancePerMatch {
                            LabeledContent("Distance", value: String(format: "%.1f km · %.1f per match",
                                                                     activity.distanceMeters / 1000, perMatch / 1000))
                        }
                        if let perMatch = activity.stepsPerMatch {
                            LabeledContent("Steps", value: "\(activity.steps.formatted()) · \(perMatch.formatted()) per match")
                        }
                        if let average = activity.averageHeartRate {
                            LabeledContent("Heart rate", value: "\(Int(average)) avg · \(Int(activity.maxHeartRate ?? 0)) highest")
                        }
                        if activity.activeCalories > 0 {
                            LabeledContent("Active energy", value: "\(Int(activity.activeCalories).formatted()) kcal")
                        }
                    }
                } header: {
                    Text("On the move")
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
