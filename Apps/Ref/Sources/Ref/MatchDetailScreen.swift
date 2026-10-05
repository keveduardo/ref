import RefKit
import SwiftUI

/// One match: the score, the fitness it cost, the timeline — and the share
/// sheet. For an unplayed match, what it is waiting for.
struct MatchDetailScreen: View {
    let store: PhoneStore
    let match: Match

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var editing = false

    var body: some View {
        List {
            Section {
                header
                if let crew = MatchReport.assistants(match.setup) {
                    LabeledContent("Assistant referees", value: crew)
                }
            }

            if match.isFinished {
                if let metrics = match.metrics {
                    metricsSection(metrics)
                }
                movementSection
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
                    if store.onWatch.contains(where: { $0.id == match.id }) {
                        Label("Running on the watch", systemImage: "applewatch.radiowaves.left.and.right")
                        Text("Edit names, colours and assistant referees here; the watch picks them up, mid-match too.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("On the watch's list", systemImage: "applewatch")
                        Text("Open RefTime on the watch: it is under From the phone, while the two are near each other.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Delete match", role: .destructive) { confirmingDelete = true }
            }
        }
        .themedBackground()
        .navigationTitle("Match")
        .toolbar {
            // Only before it is played: a finished match is a record.
            if !match.isFinished {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            MatchEditScreen(store: store, match: match)
        }
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

    /// The pitch diagram and what it says — once the route has arrived.
    @ViewBuilder
    private var movementSection: some View {
        if let route = store.route(for: match.id), !route.isEmpty,
           let frame = PitchFrame.resolve(marked: match.pitch, route: route) {
            let size = match.setup.pitchSize
            let report = MovementReport.make(points: route, frame: frame, size: size, clock: match.clock)
            Section {
                PitchHeatmap(report: report, size: size)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                ForEach(Array(report.distanceByHalf.enumerated()), id: \.offset) { index, metres in
                    LabeledContent(index == 0 ? "First half" : index == 1 ? "Second half" : "Half \(index + 1)",
                                   value: String(format: "%.2f km", metres / 1000))
                }
                LabeledContent("Top speed", value: String(format: "%.1f km/h", report.topSpeed * 3.6))
                LabeledContent("Sprints (20+ km/h)", value: "\(report.sprints)")
                LabeledContent("Thirds", value: report.thirds
                    .map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: " · "))
                LabeledContent("On the diagonal", value: "\(Int((report.onDiagonal * 100).rounded()))%")
            } header: {
                Text("Movement")
            } footer: {
                Text(frame.marked
                     ? "Field marked on the watch; the goal you faced is on the right. Thirds read left to right."
                     : "Field worked out from your running. Tap Mark field on the watch before kick-off for an exact map.")
            }
        }
    }

    private func metricsSection(_ metrics: MatchMetrics) -> some View {
        Section("On the whistle") {
            if let meters = metrics.distanceMeters {
                LabeledContent("Distance", value: String(format: "%.1f km", meters / 1000))
            }
            if let steps = metrics.steps {
                LabeledContent("Steps", value: steps.formatted())
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
