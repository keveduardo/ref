import Foundation

/// One line of the match report.
public struct TimelineEntry: Codable, Sendable, Equatable {
    public var half: Int
    /// The minute inside the half, 1-based, capped at the half length.
    public var minute: Int
    /// Minutes of added time past the half length; 0 in normal time.
    public var added: Int
    public var text: String

    public init(half: Int, minute: Int, added: Int, text: String) {
        self.half = half
        self.minute = minute
        self.added = added
        self.text = text
    }

    /// "12'", "45+2'".
    public var stamp: String {
        added > 0 ? "\(minute)+\(added)'" : "\(minute)'"
    }

    /// "45+2' Goal — Home #9".
    public var line: String { "\(stamp) \(text)" }

    /// The divider a list needs to keep the minutes honest: the second half
    /// starts over at 1, so a flat list reads 45+3' then 28'.
    public var halfTitle: String {
        switch half {
        case 1: "First half"
        case 2: "Second half"
        default: "Half \(half)"
        }
    }
}

public struct HalfSummary: Codable, Sendable, Equatable {
    public var half: Int
    public var homeGoals: Int
    public var awayGoals: Int
    /// Added time as *announced* for this half, when it was recorded.
    public var announcedAdded: TimeInterval

    public init(half: Int, homeGoals: Int, awayGoals: Int, announcedAdded: TimeInterval) {
        self.half = half
        self.homeGoals = homeGoals
        self.awayGoals = awayGoals
        self.announcedAdded = announcedAdded
    }
}

public struct MatchTotals: Codable, Sendable, Equatable {
    public var homeGoals: Int
    public var awayGoals: Int
    public var yellowCards: Int
    public var redCards: Int
    public var sinBins: Int
    public var substitutions: Int

    public init(homeGoals: Int = 0, awayGoals: Int = 0, yellowCards: Int = 0,
                redCards: Int = 0, sinBins: Int = 0, substitutions: Int = 0) {
        self.homeGoals = homeGoals
        self.awayGoals = awayGoals
        self.yellowCards = yellowCards
        self.redCards = redCards
        self.sinBins = sinBins
        self.substitutions = substitutions
    }
}

/// The report the phone shows and shares. Built from the log, like everything
/// else — there is no second copy of the match anywhere in the app.
public struct MatchReport: Codable, Sendable, Equatable {
    public var score: Score
    public var timeline: [TimelineEntry]
    public var halves: [HalfSummary]
    public var totals: MatchTotals

    public init(score: Score, timeline: [TimelineEntry], halves: [HalfSummary], totals: MatchTotals) {
        self.score = score
        self.timeline = timeline
        self.halves = halves
        self.totals = totals
    }

    public static func make(from match: Match) -> MatchReport {
        let clock = match.clock
        let score = match.score

        var timeline: [TimelineEntry] = []
        var totals = MatchTotals(homeGoals: score.home, awayGoals: score.away)

        for event in match.events.events {
            switch event.kind {
            case .yellowCard: totals.yellowCards += 1
            case .secondYellow: totals.yellowCards += 1; totals.redCards += 1
            case .redCard: totals.redCards += 1
            case .sinBin: totals.sinBins += 1
            case .substitution: totals.substitutions += 1
            default: break
            }
            if let text = text(for: event.kind, in: match) {
                let stamp = stampFor(event.at, clock: clock, config: match.setup.clock)
                timeline.append(TimelineEntry(half: stamp.half, minute: stamp.minute,
                                              added: stamp.added, text: text))
            }
        }

        let halves = (1...max(1, match.setup.clock.halves)).map { half -> HalfSummary in
            var home = 0
            var away = 0
            for event in match.events.events {
                guard stampFor(event.at, clock: clock, config: match.setup.clock).half == half else {
                    continue
                }
                switch event.kind {
                case .goal(let side, _):
                    if side == .home { home += 1 } else { away += 1 }
                case .ownGoal(let side, _):
                    if side == .home { away += 1 } else { home += 1 }
                default:
                    break
                }
            }
            return HalfSummary(half: half, homeGoals: home, awayGoals: away,
                               announcedAdded: clock.announcedAdded(half: half, at: .distantFuture))
        }

        return MatchReport(score: score, timeline: timeline, halves: halves, totals: totals)
    }

    /// One event as the report words it — "Yellow card — ARS #7" — or nil
    /// for the clock's own bookkeeping. The watch's undo button reuses it, so
    /// the referee takes back exactly the line the report would have shown.
    public static func text(for kind: MatchEvent.Kind, in match: Match) -> String? {
        switch kind {
        case .goal(let side, let scorer):
            return "Goal — \(describe(side, scorer, in: match))"
        case .ownGoal(let side, let scorer):
            return "Own goal — \(describe(side, scorer, in: match))"
        case .disallowedGoal(let side):
            return "Goal disallowed — \(match.setup.team(side).name)"
        case .yellowCard(let side, let player):
            return "Yellow card — \(describe(side, player, in: match))"
        case .secondYellow(let side, let player):
            return "Second yellow, sent off — \(describe(side, player, in: match))"
        case .redCard(let side, let player):
            return "Red card — \(describe(side, player, in: match))"
        case .sinBin(let side, let player, let minutes):
            return "Sin bin (\(minutes)′) — \(describe(side, player, in: match))"
        case .sinBinEnd(let side, let player):
            return "Back from the sin bin — \(describe(side, player, in: match))"
        case .substitution(let side, let off, let on):
            return "Substitution — \(match.setup.team(side).abbreviation) #\(off.number) off, #\(on.number) on"
        case .note(let note):
            return note
        case .quarterBreak:
            return "Quarter break"
        case .addedTime(let half, let seconds):
            let minutes = Int(seconds / 60)
            let rem = Int(seconds) % 60
            return "Added time, \(ordinal(half)) half: \(minutes)′\(rem == 0 ? "" : String(format: "%02d″", rem))"
        default:
            return nil // kick-offs, halves, pauses, voids — the clock's own bookkeeping
        }
    }

    // MARK: - Text for the share sheet

    public func shareText(match: Match) -> String {
        var lines: [String] = []
        let home = match.setup.home.name
        let away = match.setup.away.name
        lines.append("\(home) \(score.home)–\(score.away) \(away)")
        if let competition = match.setup.competition, !competition.isEmpty {
            lines.append(competition)
        }
        lines.append("")
        for entry in timeline {
            lines.append(entry.line)
        }
        lines.append("")
        var totalBits: [String] = []
        if totals.yellowCards > 0 { totalBits.append("\(totals.yellowCards) yellow") }
        if totals.redCards > 0 { totalBits.append("\(totals.redCards) red") }
        if totals.sinBins > 0 { totalBits.append("\(totals.sinBins) sin bin\(totals.sinBins == 1 ? "" : "s")") }
        if totals.substitutions > 0 { totalBits.append("\(totals.substitutions) subs") }
        lines.append(totalBits.isEmpty ? "No cards." : totalBits.joined(separator: ", ") + ".")
        if let metrics = match.metrics, let meters = metrics.distanceMeters {
            lines.append(String(format: "Distance %.1f km.", meters / 1000))
        }
        if let steps = match.metrics?.steps {
            lines.append("\(steps.formatted()) steps.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Stamps

    struct Stamp { var half: Int; var minute: Int; var added: Int }

    /// Which half an event happened in, and the referee's notation for when:
    /// "12'", "45'", "45+2'". Past the half length the minute is the half's
    /// own (45) and the added minutes count the way a referee writes them.
    static func stampFor(_ at: Date, clock: MatchClock, config: ClockConfig) -> Stamp {
        let half = clock.currentHalf(at: at)
        let elapsed = clock.elapsed(inHalf: half, at: at)
        let halfMinutes = max(1, Int(config.halfLength / 60))
        if elapsed <= config.halfLength {
            return Stamp(half: half, minute: min(Int(elapsed / 60) + 1, halfMinutes), added: 0)
        }
        let overrun = elapsed - config.halfLength
        return Stamp(half: half, minute: halfMinutes, added: max(1, Int(overrun / 60)))
    }

    private static func ordinal(_ half: Int) -> String {
        switch half {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(half)th"
        }
    }

    private static func describe(_ side: TeamSide, _ player: PlayerRef?, in match: Match) -> String {
        let team = match.setup.team(side)
        guard let player else { return team.name }
        if player.number > 0 { return "\(team.abbreviation) #\(player.number)" }
        if let id = player.id, let name = name(of: id, in: match) {
            return "\(team.abbreviation) \(name)"
        }
        return team.name
    }

    private static func name(of id: UUID, in match: Match) -> String? {
        for squad in match.setup.squads {
            if let found = squad.players.first(where: { $0.id == id }) {
                return found.name
            }
        }
        return nil
    }
}
