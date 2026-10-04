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

        public init(setups: [MatchSetup]) {
            self.version = SyncPayload.version
            self.setups = setups
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
