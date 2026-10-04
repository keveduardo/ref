import RefKit
import SwiftUI

/// The phone's home — matches, teams and settings. P0 is a skeleton; the real
/// screens are P3. What is real here already: the watch link's state, so the
/// WatchConnectivity skeleton is exercised on every render.
struct RefScreen: View {
    @State private var link = PhoneLink()

    var body: some View {
        NavigationStack {
            List {
                Section("Match") {
                    Text("Set a match up here, then send it to the watch.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Quick start", value: "On the watch")
                }
                Section("Watch") {
                    LabeledContent("Link", value: link.status)
                }
            }
            .navigationTitle("Ref")
        }
    }
}

struct SetupPlaceholder: View {
    var body: some View {
        ContentUnavailableView("New match", systemImage: "sportscourt",
                               description: Text("Teams, competition, half length — P3."))
    }
}

struct ReportPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Match report", systemImage: "list.bullet.rectangle",
                               description: Text("The timeline, score and fitness — P3."))
    }
}

struct StatsPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Season", systemImage: "chart.bar",
                               description: Text("Matches, cards, sin bins — P3."))
    }
}
