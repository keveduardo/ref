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
    /// The phone's defaults, for quick start. They arrive with every
    /// assignment, and are kept on disk with it.
    private(set) var defaults: MatchDefaults = .standard
    /// Finished matches waiting for the session to activate. Once handed to
    /// `transferUserInfo`, the system owns the delivery (and keeps it across
    /// a relaunch); before that, a match sent at the wrong moment was simply
    /// dropped.
    private var pending: [Match] = []
    private var pendingRoutes: [SyncPayload.Route] = []

    override init() {
        super.init()
        if let saved = Self.loadAssignment() {
            assignments = saved.setups
            defaults = saved.defaults
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending

    /// The finished match, on its way to the phone's shelf.
    func send(_ match: Match) {
        guard activated else {
            pending.append(match)
            return
        }
        guard let data = try? SyncPayload.encode(SyncPayload.FinishedMatch(match: match)) else {
            return
        }
        WCSession.default.transferUserInfo(["finishedMatch": data])
    }

    /// The route behind the pitch diagram, as a file — too big for user
    /// info. The system owns the delivery once it is queued.
    func send(_ route: SyncPayload.Route) {
        guard activated else {
            pendingRoutes.append(route)
            return
        }
        guard let data = try? SyncPayload.encode(route) else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("route-\(route.matchID.uuidString).json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        WCSession.default.transferFile(file, metadata: ["kind": "route"])
    }

    private func flushPending() {
        let waiting = pending
        pending = []
        for match in waiting { send(match) }
        let routes = pendingRoutes
        pendingRoutes = []
        for route in routes { send(route) }
    }

    // MARK: - Receiving

    private func ingest(assignmentData: Data?) {
        guard let assignmentData,
              let assignment = try? SyncPayload.decode(SyncPayload.Assignment.self,
                                                       from: assignmentData) else {
            return
        }
        assignments = assignment.setups
        defaults = assignment.defaults
        Self.saveAssignment(assignment)
    }

    // MARK: - Where the assignment lives on disk

    private static var file: URL {
        MatchSession.containerDirectory.appendingPathComponent("assignments.json")
    }

    /// Kept as the envelope it arrived in — the same encoding as the wire.
    private static func loadAssignment() -> SyncPayload.Assignment? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? SyncPayload.decode(SyncPayload.Assignment.self, from: data)
    }

    private static func saveAssignment(_ assignment: SyncPayload.Assignment) {
        try? FileManager.default.createDirectory(at: MatchSession.containerDirectory,
                                                 withIntermediateDirectories: true)
        try? SyncPayload.encode(assignment).write(to: file, options: .atomic)
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let activated = activationState == .activated
        Task { @MainActor in
            self.activated = activated
            if activated { self.flushPending() }
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
