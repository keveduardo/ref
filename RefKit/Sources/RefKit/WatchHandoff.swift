import Foundation

/// The phone's record of which matches the watch has in hand.
///
/// `onWatch` is every match the watch took on — a quick start or one picked
/// from the phone's list — until it is finished, put back, or the watch
/// reports something else running. `madeOnWatch` is only the quick starts:
/// matches the watch created, which the phone did not have before.
///
/// The difference matters when a match is put back before kick-off ("Choose
/// another match"): a quick start was never anything but a placeholder and
/// goes, while a fixture from the phone's list must survive with its edits
/// (Fable audit, 2026-11-13: backing out of the 7 PM game deleted it).
public struct WatchHandoff: Equatable, Sendable {
    public private(set) var onWatch: Set<UUID>
    public private(set) var madeOnWatch: Set<UUID>

    public init(onWatch: Set<UUID> = [], madeOnWatch: Set<UUID> = []) {
        self.onWatch = onWatch
        self.madeOnWatch = madeOnWatch
    }

    /// The watch started `id`. `phoneHadIt` is whether the phone already
    /// had that match — if not, the watch made it.
    public mutating func started(_ id: UUID, phoneHadIt: Bool) {
        onWatch.insert(id)
        if !phoneHadIt { madeOnWatch.insert(id) }
    }

    /// The watch's match in hand is `id` (nil: none). Any other is no
    /// longer on it. Quick starts keep their mark — a "put back" may still
    /// be on its way, and it must still be able to delete them.
    public mutating func running(_ id: UUID?) {
        onWatch = onWatch.filter { $0 == id }
    }

    /// Put back on the watch before kick-off. True when the match should be
    /// deleted: only a quick start, never a match the phone gave it.
    public mutating func cancelled(_ id: UUID) -> Bool {
        onWatch.remove(id)
        return madeOnWatch.remove(id) != nil
    }

    /// Back from the watch finished, or deleted on the phone: forgotten.
    public mutating func forget(_ id: UUID) {
        onWatch.remove(id)
        madeOnWatch.remove(id)
    }
}

/// The watch's side of "did the phone get it?" (2026-11-14). Nothing on the
/// watch can see whether a finished match reached the phone — so the phone
/// says which matches it is still waiting on, and the watch sends again any
/// of those its shelf holds finished. A match deleted on the phone is not on
/// that list, so it is never brought back; one the phone has is not either.
public enum WatchResend {
    public static func toResend(shelf: [Match], awaiting: Set<UUID>, inHand: UUID?,
                                at now: Date = Date()) -> [Match] {
        shelf.filter { match in
            awaiting.contains(match.id) && match.id != inHand
                && match.clock.phase(at: now) == .fullTime
        }
    }
}

extension MatchStore {
    /// Saves a record onto the shelf, keeping any event the shelf's copy
    /// already has — a late goal saved there while this copy was on its way
    /// is not overwritten by it.
    public func saveUnion(_ match: Match) throws {
        var merged = match
        if let shelved = try? load(id: match.id) {
            merged.events.append(contentsOf: shelved.events.recorded)
            merged.metrics = match.metrics ?? shelved.metrics
            merged.pitch = match.pitch ?? shelved.pitch
        }
        try save(merged)
    }
}
