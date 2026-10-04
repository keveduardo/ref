import Foundation

/// What travels between the phone and the watch, and the rules for it.
///
/// Every envelope carries a version; a receiver refuses one from the future
/// rather than guessing at fields it has never heard of. The rules mirror
/// `RowingKit/MirrorMessage.swift`: the payloads are deliberately not the
/// whole domain — only what the other side needs — and they are plain Codable
/// so the transport (WatchConnectivity) never leaks into this package.
public enum SyncPayload {
    public static let version = 1

    /// Phone → watch, before a match: the setups the referee may start today.
    /// Sent as `applicationContext` (latest-wins — a newer assignment simply
    /// replaces an older one).
    public struct Assignment: Codable, Sendable, Equatable {
        public var version: Int
        public var setups: [MatchSetup]
        /// The phone's defaults, for a quick start on the watch.
        public var defaults: MatchDefaults

        public init(setups: [MatchSetup], defaults: MatchDefaults = .standard) {
            self.version = SyncPayload.version
            self.setups = setups
            self.defaults = defaults
        }
    }

    /// Watch → phone, after a match: the finished record, metrics included.
    /// Sent as `transferUserInfo` (queued and delivered when it can), which
    /// means it may arrive twice — the phone merges by `Match.id`.
    public struct FinishedMatch: Codable, Sendable, Equatable {
        public var version: Int
        public var match: Match

        public init(match: Match) {
            self.version = SyncPayload.version
            self.match = match
        }
    }

    /// Watch → phone, after a match: the route behind the pitch diagram. Too
    /// big for user info (a fix every 2 s for 100 minutes), so it travels as
    /// a file (`transferFile`), and the phone files it by match id.
    public struct Route: Codable, Sendable, Equatable {
        public var version: Int
        public var matchID: UUID
        public var points: [RoutePoint]

        public init(matchID: UUID, points: [RoutePoint]) {
            self.version = SyncPayload.version
            self.matchID = matchID
            self.points = points
        }

        /// One fix every `interval` seconds at most — enough for a heatmap,
        /// a fraction of the size.
        public static func thinned(_ points: [RoutePoint], every interval: TimeInterval = 2) -> [RoutePoint] {
            var kept: [RoutePoint] = []
            for point in points.sorted(by: { $0.at < $1.at }) {
                if let last = kept.last, point.at.timeIntervalSince(last.at) < interval { continue }
                kept.append(point)
            }
            return kept
        }
    }

    public enum Refusal: Error, Equatable {
        /// The sender speaks a newer protocol than this build understands.
        case futureVersion(Int)
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let probe = try decoder.decode(VersionProbe.self, from: data)
        guard probe.version <= version else {
            throw Refusal.futureVersion(probe.version)
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// Reads just the envelope's version, before anything else is decoded.
private struct VersionProbe: Decodable {
    let version: Int
}
