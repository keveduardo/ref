import Foundation
import Observation
import RefKit
import WatchConnectivity

/// The phone's half of the link to the watch.
///
/// Assignments go out with `updateApplicationContext` (latest-wins: the watch
/// always has the newest set of matches); finished matches come back as
/// `transferUserInfo` and are handed to `onFinished`, which the app wires to
/// the store.
///
/// The concurrency pattern is Swim's (`Apps/Swim/Sources/SwimSession.swift`,
/// explained in SWIM.md): `@MainActor @Observable`, every delegate method
/// `nonisolated`, only Sendable values crossing the hop.
@MainActor @Observable final class PhoneLink: NSObject {
    private(set) var activated = false

    /// ! `@MainActor`, not a bare closure: the app assigns this from a
    /// main-actor context, and in Swift 6 a non-Sendable closure keeps that
    /// isolation — handing it to a non-isolated parameter is an error.
    private let onFinished: (@MainActor (Match) -> Void)?
    private let onRoute: (@MainActor () -> Void)?

    var status: String {
        if !activated { return "Not activated" }
        return WCSession.default.isPaired ? "Connected" : "No watch paired"
    }

    init(onFinished: (@MainActor (Match) -> Void)? = nil,
         onRoute: (@MainActor () -> Void)? = nil) {
        self.onFinished = onFinished
        self.onRoute = onRoute
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending

    /// The upcoming matches, as the watch will offer them, and the defaults
    /// its quick start uses. Silent when there is nobody to say it to — the
    /// app sends again when activation completes, and on every change.
    func sendAssignment(_ setups: [MatchSetup], defaults: MatchDefaults) {
        guard activated, WCSession.default.isPaired,
              let data = try? SyncPayload.encode(SyncPayload.Assignment(setups: setups,
                                                                        defaults: defaults)) else {
            return
        }
        try? WCSession.default.updateApplicationContext(["assignment": data])
    }

    // MARK: - Receiving

    private func ingest(matchData: Data?) {
        guard let matchData,
              let payload = try? SyncPayload.decode(SyncPayload.FinishedMatch.self,
                                                    from: matchData) else {
            return
        }
        onFinished?(payload.match)
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let activated = activationState == .activated
        Task { @MainActor in self.activated = activated }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The phone moved to a new watch; without reactivating here the link
        // silently stops receiving.
        WCSession.default.activate()
    }
    #endif

    /// A route, as a file. ! Filed here, synchronously: the system deletes
    /// the transferred file when this method returns.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL), RouteFiles.file(data) else { return }
        Task { @MainActor in self.onRoute?() }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Only the Sendable piece crosses the hop — a `[String: Any]` cannot.
        let data = userInfo["finishedMatch"] as? Data
        Task { @MainActor in self.ingest(matchData: data) }
    }
}
