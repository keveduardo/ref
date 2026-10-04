import RefKit
import SwiftUI

/// One match: the score, the fitness it cost, the timeline — and the share
/// sheet. For an unplayed match, what it is waiting for.
struct MatchDetailScreen: View {
    let store: PhoneStore
    let match: Match

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                header
            }

            if match.isFinished {
                if let metrics = match.metrics {
                    metricsSection(metrics)
                }
                let entries = match.report.timeline
                if entries.isEmpty {
                    Section("Timeline") {
                        Text("No incidents.").foregroundStyle(.secondary)
                    }
                } else {
                    // Grouped by half. Without the grouping, a report reads
                    // 13' → 31' → 45+3' → 28' → 36', which is right and looks
                    // wrong — the second half's minutes start over.
                    ForEach(halfGroups(entries)) { group in
                        Section(group.entries.first?.halfTitle ?? "Timeline") {
                            ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                Text(entry.line)
                            }
                        }
                    }
                }
                Section {
                    ShareLink(item: match.report.shareText(match: match)) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                }
            } else {
                Section("Watch") {
                    Label("Sent to watch", systemImage: "applewatch")
                    Text("An upcoming match travels to the watch automatically while the two are near each other.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Delete match", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Match")
        .confirmationDialog("Delete this match?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                store.delete(match)
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                teamLabel(match.setup.home)
                Text(match.isFinished ? match.score.text : "vs")
                    .font(.title2.bold())
                    .monospacedDigit()
                teamLabel(match.setup.away)
            }
            .frame(maxWidth: .infinity)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func teamLabel(_ team: Team) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(team.color.phoneColor)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                .frame(width: 14, height: 14)
            Text(team.abbreviation)
                .font(.headline)
                .foregroundStyle(team.color.phoneColorInk)
            Text(team.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricsSection(_ metrics: MatchMetrics) -> some View {
        Section("On the whistle") {
            if let meters = metrics.distanceMeters {
                LabeledContent("Distance", value: String(format: "%.1f km", meters / 1000))
            }
            if let average = metrics.averageHeartRate {
                LabeledContent("Heart rate", value: "\(Int(average)) avg / \(Int(metrics.maxHeartRate ?? 0)) max")
            }
            if let calories = metrics.activeCalories {
                LabeledContent("Active energy", value: "\(Int(calories)) kcal")
            }
        }
    }

    private var subtitle: String {
        let when = (match.setup.kickOff ?? match.createdAt).formatted(date: .abbreviated, time: .shortened)
        if let competition = match.setup.competition, !competition.isEmpty {
            return "\(competition) · \(when)"
        }
        return when
    }

    // MARK: - Timeline grouping

    private struct HalfGroup: Identifiable {
        var half: Int
        var entries: [TimelineEntry]
        var id: Int { half }
    }

    private func halfGroups(_ entries: [TimelineEntry]) -> [HalfGroup] {
        var groups: [HalfGroup] = []
        for entry in entries {
            if groups.last?.half == entry.half {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(HalfGroup(half: entry.half, entries: [entry]))
            }
        }
        return groups
    }
}

/// RefKit's colour tokens, as the phone sees them.
///
/// Two roles, because one colour cannot do both: `phoneColor` fills a dot
/// (white is a real team colour and a white dot on a white card needs its
/// hairline stroke), and `phoneColorInk` is for *text*, where white would be
/// invisible in light mode — a white team's name is shown in secondary ink
/// rather than unreadable.
extension TeamColor {
    var phoneColor: Color {
        switch self {
        case .red: .red
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .purple: .purple
        case .black: .primary
        case .white: .white
        }
    }

    var phoneColorInk: Color {
        self == .white ? .secondary : phoneColor
    }
}
