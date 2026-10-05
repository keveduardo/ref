import Foundation

/// A game as a referee scheduler announces it — read from the text of a
/// reminder email, so a match can be set up without typing.
///
/// The format is CGI Sports' "Game reminder" email (the AYSO referee
/// scheduler several regions use, Region 34 among them). It has no calendar
/// feed and no API (2026-10-04), but its reminders are one field per line:
///
///     Game ID: 120107
///     CR: <referee>
///     AR1: <referee>
///     AR2:
///     Division: BC Boys 12U
///     Date: Nov 16, 2025 Sun
///     Time: 8:00 AM
///     Location: Alta Vista
///     Field: AVP
///     Home: A1 02 <coach>
///     Visitor: A2 07 <coach>
public struct ScheduledGame: Sendable, Equatable {
    public var gameID: String
    public var division: String
    public var kickOff: Date
    public var location: String?
    public var field: String?
    public var home: String
    public var visitor: String
    /// Who holds each slot, as the email names them ("CR", "AR1", "AR2").
    public var crew: [String: String]

    /// The AYSO preset the division names, when it is one RefTime has:
    /// "BC Boys 12U", "Girls 10U", "U14 G" and the like.
    public var format: MatchFormat? {
        let text = division.lowercased()
        guard let age = Self.age(in: text) else { return nil }
        let gender: MatchFormat.Gender? =
            text.range(of: #"\bgirls?\b|\bg\b|\d+u?g\b|\bg\d+"#, options: .regularExpression) != nil ? .girls
            : text.range(of: #"\bboys?\b|\bb\b|\d+u?b\b|\bb\d+"#, options: .regularExpression) != nil ? .boys
            : nil
        guard let gender else { return nil }
        return MatchFormat.preset(id: "ayso-\(age)u-\(gender.rawValue)")
    }

    /// "Alta Vista · AVP".
    public var venue: String? {
        let parts = [location, field].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The match this game becomes. Its id comes from the scheduler's game
    /// id, so importing the same reminder twice updates one match rather than
    /// making two.
    public func matchSetup(halfTimeMinutes: Int = MatchDefaults.standard.halfTimeMinutes,
                           countsDown: Bool = true) -> MatchSetup {
        let format = self.format
        let halfMinutes = format?.halfMinutes ?? MatchDefaults.standard.halfMinutes
        let title = format?.title ?? division
        return MatchSetup(
            id: Self.matchID(gameID),
            home: Team(name: home, abbreviation: Self.shortName(home),
                       color: Team.placeholder(.home).color),
            away: Team(name: visitor, abbreviation: Self.shortName(visitor),
                       color: Team.placeholder(.away).color),
            competition: [title, venue].compactMap { $0 }.joined(separator: " — "),
            kickOff: kickOff,
            clock: ClockConfig(halfMinutes: halfMinutes, countsDown: countsDown),
            formatID: format?.id,
            halfTimeMinutes: halfTimeMinutes,
            quarterBreak: format?.quarterSubstitutions == true ? QuarterBreak() : nil,
            ar1: crew["AR1"], ar2: crew["AR2"])
    }

    // MARK: - Reading the email

    /// Every game in the text — a reminder usually holds one, but a pasted
    /// run of them holds several. Games missing a date, time or team are
    /// skipped rather than guessed at.
    public static func parse(_ text: String, timeZone: TimeZone = .current) -> [ScheduledGame] {
        // Each game starts at its "Game ID:" line.
        let lines = text.replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var blocks: [[String: String]] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...]
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if key == "game id" { blocks.append([:]) }
            guard !blocks.isEmpty else { continue }
            blocks[blocks.count - 1][key] = value
        }
        return blocks.compactMap { game(from: $0, timeZone: timeZone) }
    }

    private static func game(from fields: [String: String], timeZone: TimeZone) -> ScheduledGame? {
        guard let id = fields["game id"], !id.isEmpty,
              let home = fields["home"], !home.isEmpty,
              let visitor = fields["visitor"] ?? fields["away"], !visitor.isEmpty,
              let date = fields["date"], let time = fields["time"],
              let kickOff = kickOff(date: date, time: time, timeZone: timeZone) else { return nil }
        var crew: [String: String] = [:]
        for slot in ["cr", "ar1", "ar2", "4th"] {
            if let name = fields[slot], !name.isEmpty { crew[slot.uppercased()] = name }
        }
        return ScheduledGame(gameID: id, division: fields["division"] ?? "",
                             kickOff: kickOff, location: fields["location"],
                             field: fields["field"], home: home, visitor: visitor, crew: crew)
    }

    /// "Nov 16, 2025 Sun" + "8:00 AM", in the referee's own time zone — the
    /// email gives wall-clock time at the field.
    static func kickOff(date: String, time: String, timeZone: TimeZone) -> Date? {
        // Drop a trailing weekday ("Sun"), which the formatter would refuse.
        let day = date.replacingOccurrences(of: #"\s+[A-Za-z]{3,9}\.?$"#, with: "",
                                            options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for pattern in ["MMM d, yyyy h:mm a", "MMMM d, yyyy h:mm a", "M/d/yyyy h:mm a"] {
            formatter.dateFormat = pattern
            if let parsed = formatter.date(from: "\(day) \(time.uppercased())") { return parsed }
        }
        return nil
    }

    static func age(in text: String) -> Int? {
        for pattern in [#"(\d{1,2})\s*u\b"#, #"\bu\s*-?\s*(\d{1,2})\b"#, #"(\d{1,2})u[gb]\b"#] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return Int(text[range])
            }
        }
        return nil
    }

    /// "A1 02 Smith" → "SMI": the coach's name is what the referee knows the
    /// team by; the bracket code in front of it is not.
    static func shortName(_ team: String) -> String {
        let last = team.split(whereSeparator: \.isWhitespace).last { $0.contains(where: \.isLetter) }
        return String((last ?? Substring(team)).filter(\.isLetter).prefix(3)).uppercased()
    }

    /// A stable match id for a scheduler game id: the digits, zero-padded
    /// into the last group of a fixed UUID. Same game, same match.
    static func matchID(_ gameID: String) -> UUID {
        let digits = String(gameID.filter(\.isNumber).suffix(12))
        let padded = String(repeating: "0", count: 12 - digits.count) + digits
        return UUID(uuidString: "C6150000-0000-4000-8000-\(padded)") ?? UUID()
    }
}
