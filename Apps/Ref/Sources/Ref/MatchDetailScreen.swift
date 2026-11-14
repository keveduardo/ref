import RefKit
import SwiftUI
import UIKit

/// One match: the score, the fitness it cost, the timeline — and the share
/// sheet. For an unplayed match, what it is waiting for.
struct MatchDetailScreen: View {
    let store: PhoneStore
    private let initial: Match

    init(store: PhoneStore, match: Match) {
        self.store = store
        self.initial = match
    }

    /// The store's copy, so a goal added here shows at once.
    private var match: Match { store.all.first { $0.id == initial.id } ?? initial }

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @AppStorage("ref.distanceUnit") private var unit = DistanceUnit.default()
    @State private var editing = false
    @State private var addingGoal = false

    var body: some View {
        List {
            Section {
                header
                ForEach(TeamSide.allCases, id: \.self) { side in
                    let team = match.setup.team(side)
                    if let details = team.details {
                        LabeledContent(team.name, value: details)
                    }
                }
                if let crew = MatchReport.referees(match.setup) {
                    LabeledContent("Referees", value: crew)
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
                    // A goal the watch missed — scored on the whistle while
                    // the alarm rang (Kevin, 2026-11-06).
                    Button {
                        addingGoal = true
                    } label: {
                        Label("Add a goal", systemImage: "soccerball")
                    }
                    ShareLink(item: match.report.shareText(match: match, unit: unit)) {
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
        .sheet(isPresented: $addingGoal) {
            AddGoalScreen(store: store, match: match)
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
                teamLabel(.home)
                Text(match.isFinished ? match.score.text : "vs")
                    .font(.title2.bold())
                    .monospacedDigit()
                teamLabel(.away)
            }
            .frame(maxWidth: .infinity)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// A team's dot, short name and name. A tap opens its colours (Kevin,
    /// 2026-11-12: "click directly on the color icon to change the uniform
    /// color rather than having to go to edit"); the choice is saved at once
    /// and reaches the watch like any edit, mid-match too.
    private func teamLabel(_ side: TeamSide) -> some View {
        let team = match.setup.team(side)
        return Menu {
            Picker("\(side == .home ? "Home" : "Away") colour", selection: Binding(
                get: { team.color },
                set: { setColor($0, for: side) })) {
                ForEach(TeamColor.allCases, id: \.self) { token in
                    Label {
                        Text(token.rawValue.capitalized)
                    } icon: {
                        Image(uiImage: token.swatch)
                    }
                    .tag(token)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Circle()
                    .fill(team.color.phoneColor)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                    .frame(width: 22, height: 22)
                Text(team.abbreviation)
                    .font(.headline)
                    .foregroundStyle(team.color.phoneColorInk)
                Text(team.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Change this team's colour")
    }

    private func setColor(_ color: TeamColor, for side: TeamSide) {
        var updated = match
        updated.setup.setColor(color, for: side)
        store.save(updated)
    }

    /// The pitch diagram and what it says — once the route has arrived.
    @ViewBuilder
    private var movementSection: some View {
        if let route = store.route(for: match.id), !route.isEmpty,
           let frame = PitchFrame.resolve(marked: match.pitch, route: route,
                                          role: match.setup.myRole, size: match.setup.pitchSize) {
            let size = match.setup.pitchSize
            let assistant = match.setup.myRole?.isAssistant == true
            let report = MovementReport.make(points: route, frame: frame, size: size, clock: match.clock)
            Section {
                PitchHeatmap(report: report, size: size)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                ForEach(Array(report.distanceByHalf.enumerated()), id: \.offset) { index, metres in
                    LabeledContent(index == 0 ? "First half" : index == 1 ? "Second half" : "Half \(index + 1)",
                                   value: unit.format(metres: metres, decimals: 2))
                }
                LabeledContent("Top speed", value: unit.formatSpeed(metresPerSecond: report.topSpeed))
                LabeledContent("Sprints (\(unit.sprintThreshold)+)", value: "\(report.sprints)")
                LabeledContent("Thirds", value: report.thirds
                    .map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: " · "))
                // An assistant's match is the touchline, not the diagonal.
                if assistant {
                    LabeledContent("On the touchline", value: "\(Int((report.onTouchline * 100).rounded()))%")
                } else {
                    LabeledContent("On the diagonal", value: "\(Int((report.onDiagonal * 100).rounded()))%")
                }
            } header: {
                Text("Movement")
            } footer: {
                Text(frame.marked
                     ? "Field marked on the watch; the goal you faced is on the right. Thirds read left to right."
                     : assistant
                        ? "Field worked out from your running as an assistant: your touchline along the bottom, your half on the right. Tap Mark field on the watch at the centre spot for an exact map."
                        : "Field worked out from your running. Tap Mark field on the watch before kick-off for an exact map.")
            }
        }
    }

    private func metricsSection(_ metrics: MatchMetrics) -> some View {
        Section("On the whistle") {
            if let meters = metrics.distanceMeters {
                LabeledContent("Distance", value: unit.format(metres: meters))
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

/// A goal added after the match: which team, who (if known), and which half.
/// It goes in that half's last minute, a second before its whistle
/// (`EventLog.lateGoal`), so the score by half and the report agree.
struct AddGoalScreen: View {
    let store: PhoneStore
    let match: Match

    @Environment(\.dismiss) private var dismiss
    @State private var side: TeamSide = .home
    @State private var number = ""
    @State private var half: Int

    init(store: PhoneStore, match: Match) {
        self.store = store
        self.match = match
        // The last half by default: the goal on the final whistle.
        _half = State(initialValue: match.events.lastWhistle?.half ?? 1)
    }

    /// Halves that were played to a whistle.
    private var halves: [Int] {
        (1...max(1, match.setup.clock.halves)).filter { match.events.whistle(endingHalf: $0) != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Team", selection: $side) {
                    Text(match.setup.home.name).tag(TeamSide.home)
                    Text(match.setup.away.name).tag(TeamSide.away)
                }
                .pickerStyle(.inline)
                Section {
                    TextField("Scorer's number (optional)", text: $number)
                        .keyboardType(.numberPad)
                }
                if halves.count > 1 {
                    Picker("Half", selection: $half) {
                        ForEach(halves, id: \.self) { h in
                            Text(h == 1 ? "1st half" : h == 2 ? "2nd half" : "Half \(h)").tag(h)
                        }
                    }
                }
                Section {
                    Text("It goes in that half's last minute.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .themedBackground()
            .navigationTitle("Add a goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { add() } }
            }
        }
    }

    private func add() {
        guard let whistle = match.events.whistle(endingHalf: half) else { return }
        let scorer = Int(number.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? PlayerRef(number: $0) : nil }
        var updated = match
        updated.events.append(EventLog.lateGoal(side: side, scorer: scorer, beforeWhistle: whistle))
        store.save(updated)
        dismiss()
    }
}
