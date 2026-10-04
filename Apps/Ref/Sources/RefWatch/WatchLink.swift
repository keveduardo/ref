import Foundation
import Observation
import RefKit
import WatchConnectivity

/// The watch's half of the link to the phone.
///
/// Two directions with different guarantees, on purpose:
/// - **Assignments come down** as `applicationContext` — latest-wins, small,
///   and the last one sent is still there after a relaunch.
/// - **Finished matches go up** as `transferUserInfo` — queued and delivered
///   when it can be, which means it can also arrive twice; the phone dedupes
///   by match id.
///
/// The concurrency pattern is Swim's (SWIM.md): `@MainActor @Observable`,
/// every delegate method `nonisolated`, only Sendable values crossing the hop.
@MainActor @Observable final class WatchLink: NSObject {
    private(set) var activated = false
    /// The phone's current assignment, mirrored to disk so it survives a
    /// relaunch on the pitch.
    private(set) var assignments: [MatchSetup] = []

    override init() {
        super.init()
        assignments = Self.loadAssignments()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending

    /// The finished match, on its way to the phone's shelf.
    func send(_ match: Match) {
        guard activated,
              let data = try? SyncPayload.encode(SyncPayload.FinishedMatch(match: match)) else {
            return
        }
        WCSession.default.transferUserInfo(["finishedMatch": data])
    }

    // MARK: - Receiving

    private func ingest(assignmentData: Data?) {
        guard let assignmentData,
              let assignment = try? SyncPayload.decode(SyncPayload.Assignment.self,
                                                       from: assignmentData) else {
            return
        }
        assignments = assignment.setups
        Self.saveAssignments(assignments)
    }

    // MARK: - Where the assignment lives on disk

    private static var file: URL {
        MatchSession.containerDirectory.appendingPathComponent("assignments.json")
    }

    private static func loadAssignments() -> [MatchSetup] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MatchSetup].self, from: data)) ?? []
    }

    private static func saveAssignments(_ setups: [MatchSetup]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: MatchSession.containerDirectory,
                                                 withIntermediateDirectories: true)
        try? encoder.encode(setups).write(to: file, options: .atomic)
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let activated = activationState == .activated
        Task { @MainActor in
            self.activated = activated
            // A context that arrived before activation is still waiting here.
            // Read on the main actor — a `[String: Any]` cannot cross.
            self.ingest(assignmentData: WCSession.default.receivedApplicationContext["assignment"] as? Data)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        // Only the Sendable piece crosses the hop.
        let data = applicationContext["assignment"] as? Data
        Task { @MainActor in
            self.ingest(assignmentData: data)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // The watch is the sender of finished matches, not a receiver.
    }
}
