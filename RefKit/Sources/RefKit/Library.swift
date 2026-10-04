import Foundation

/// The referee's teams and squads, on the phone, as one JSON file.
///
/// A match embeds its own copy of both teams, so deleting a team here can
/// never break a match already recorded — the library is a convenience for
/// setting the next one up, not a foreign key.
public struct TeamLibrary: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var file: URL { directory.appendingPathComponent("teams.json") }

    /// Sorted by name — the order the phone's lists want.
    public func all() throws -> [Squad] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let squads = try decoder.decode([Squad].self, from: Data(contentsOf: file))
        return squads.sorted { $0.team.name.localizedCaseInsensitiveCompare($1.team.name) == .orderedAscending }
    }

    /// Insert or replace, by team id.
    public func save(_ squad: Squad) throws {
        var squads = (try? all()) ?? []
        if let index = squads.firstIndex(where: { $0.team.id == squad.team.id }) {
            squads[index] = squad
        } else {
            squads.append(squad)
        }
        try write(squads)
    }

    public func delete(teamID: UUID) throws {
        var squads = (try? all()) ?? []
        squads.removeAll { $0.team.id == teamID }
        try write(squads)
    }

    private func write(_ squads: [Squad]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(squads).write(to: file, options: .atomic)
    }
}
