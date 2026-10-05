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
    private let onStarted: (@MainActor (MatchSetup) -> Void)?
    private let onCancelled: (@MainActor (UUID) -> Void)?
    /// The match the watch says it is running (nil: none).
    var onWatchCurrent: (@MainActor (UUID?) -> Void)?

    var status: String {
        if !activated { return "Not activated" }
        return WCSession.default.isPaired ? "Connected" : "No watch paired"
    }

    init(onFinished: (@MainActor (Match) -> Void)? = nil,
         onRoute: (@MainActor () -> Void)? = nil,
         onStarted: (@MainActor (MatchSetup) -> Void)? = nil,
         onCancelled: (@MainActor (UUID) -> Void)? = nil) {
        self.onCancelled = onCancelled
        self.onFinished = onFinished
        self.onRoute = onRoute
        self.onStarted = onStarted
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending

    /// The upcoming matches, as the watch will offer them, and the defaults
    /// its quick start uses. Silent when there is nobody to say it to — the
    /// app sends again when activation completes, and on every change.
    ///
    /// ! Three ways, because one was not enough (Kevin, 2026-10-04: a match
    /// deleted on the phone stayed on the watch). The application context is
    /// the durable copy; a message goes too while the watch is reachable, for
    /// an instant update; and the watch asks for the latest whenever its app
    /// opens (`didReceiveMessage` below answers from `latest`). The outcome is
    /// recorded, not swallowed, and shown in Settings › Watch.
    func sendAssignment(_ setups: [MatchSetup], defaults: MatchDefaults) {
        guard let data = try? SyncPayload.encode(SyncPayload.Assignment(setups: setups,
                                                                        defaults: defaults)) else { return }
        Self.latest.set(data)
        deliver(data, count: setups.count)
    }

    private func deliver(_ data: Data, count: Int) {
        let session = WCSession.default
        guard activated else { lastSendError = "Waiting for the watch link to start"; return }
        guard session.isPaired else { lastSendError = "No watch paired"; return }
        guard session.isWatchAppInstalled else { lastSendError = "RefTime is not installed on the watch"; return }
        do {
            try session.updateApplicationContext(["assignment": data])
            lastSent = Date()
            lastSentCount = count
            lastSendError = nil
        } catch {
            lastSendError = error.localizedDescription
        }
        if session.isReachable {
            session.sendMessage(["assignment": data], replyHandler: nil, errorHandler: nil)
        }
    }

    /// The newest assignment, again — when the watch comes back in reach or
    /// its app is reinstalled.
    fileprivate func resend() {
        guard let data = Self.latest.get(),
              let assignment = try? SyncPayload.decode(SyncPayload.Assignment.self, from: data) else { return }
        deliver(data, count: assignment.setups.count)
    }

    private(set) var lastSent: Date?
    private(set) var lastSentCount = 0
    private(set) var lastSendError: String?

    /// The newest assignment, readable from the WatchConnectivity callbacks
    /// (which are not on the main actor) to answer the watch's request.
    nonisolated static let latest = DataBox()

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
        Task { @MainActor in
            self.activated = activated
            // What the watch last said it was running, from before launch.
            if let current = WCSession.default.receivedApplicationContext["currentMatch"] as? String {
                self.onWatchCurrent?(UUID(uuidString: current))
            }
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let current = applicationContext["currentMatch"] as? String else { return }
        let id = UUID(uuidString: current)
        Task { @MainActor in self.onWatchCurrent?(id) }
    }

    /// The watch asking for the latest assignment as its app opens. Answered
    /// at once from the box — the reply handler cannot wait for the main actor.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        if message["want"] as? String == "assignment", let data = Self.latest.get() {
            replyHandler(["assignment": data])
        } else {
            replyHandler([:])
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.resend() }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // Installed, reinstalled or updated on the watch: give it the list.
        Task { @MainActor in self.resend() }
    }

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
        // Only the Sendable pieces cross the hop — a `[String: Any]` cannot.
        let finished = userInfo["finishedMatch"] as? Data
        let started = userInfo["startedMatch"] as? Data
        let cancelled = (userInfo["cancelledMatch"] as? String).flatMap(UUID.init)
        Task { @MainActor in
            if let cancelled { self.onCancelled?(cancelled) }
            if let finished { self.ingest(matchData: finished) }
            if let started,
               let payload = try? SyncPayload.decode(SyncPayload.StartedMatch.self, from: started) {
                self.onStarted?(payload.setup)
            }
        }
    }
}

/// A Data slot safe to read from any thread — the newest assignment, for the
/// watch's request, which arrives on WatchConnectivity's own queue.
final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func set(_ value: Data) { lock.withLock { data = value } }
    func get() -> Data? { lock.withLock { data } }
}
