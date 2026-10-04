import Foundation

/// Matches on disk, as plain JSON files.
///
/// Two places: `current.json` is the match in progress — rewritten on *every*
/// event, because mid-match the watch holds the only copy of the match — and
/// `matches/<id>.json` is every finished one. The directory is injected, so
/// the tests run in a temp folder and the apps point it at their own
/// container.
///
/// Dates are written as ISO-8601, whole seconds: readable in a text editor,
/// and the sub-second part of a `Date()` is dropped on the way (invisible on
/// a clock that shows minutes, and never consequential to an ordering, which
/// is by (date, id)).
public struct MatchStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var currentURL: URL { directory.appendingPathComponent("current.json") }
    private var matchesDirectory: URL { directory.appendingPathComponent("matches", isDirectory: true) }

    // MARK: - The match in progress

    /// Written after every event — the one rule that keeps a mid-match crash
    /// from costing the referee their match.
    public func saveCurrent(_ match: Match) throws {
        try write(match, to: currentURL)
    }

    public func current() throws -> Match? {
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return nil }
        return try read(currentURL)
    }

    public func clearCurrent() throws {
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return }
        try FileManager.default.removeItem(at: currentURL)
    }

    // MARK: - Finished matches

    public func save(_ match: Match) throws {
        try FileManager.default.createDirectory(at: matchesDirectory,
                                                withIntermediateDirectories: true)
        try write(match, to: matchesDirectory.appendingPathComponent("\(match.id.uuidString).json"))
    }

    /// Newest first by `createdAt`.
    public func all() throws -> [Match] {
        guard FileManager.default.fileExists(atPath: matchesDirectory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: matchesDirectory, includingPropertiesForKeys: nil)
        return try files
            .filter { $0.pathExtension == "json" }
            .map { try read($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func load(id: UUID) throws -> Match {
        try read(matchesDirectory.appendingPathComponent("\(id.uuidString).json"))
    }

    public func delete(id: UUID) throws {
        let url = matchesDirectory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - JSON

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func write(_ match: Match, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Atomic: a crash mid-write leaves the previous good file, not half
        // a JSON document.
        try Self.encoder().encode(match).write(to: url, options: .atomic)
    }

    private func read(_ url: URL) throws -> Match {
        try Self.decoder().decode(Match.self, from: Data(contentsOf: url))
    }
}
