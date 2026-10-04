import Foundation
import Observation
import WatchConnectivity

/// The watch's half of the link to the phone. P0: activation and the delegate
/// conformances only — the match coming down and the finished match going back
/// arrive with the sync work (P4).
///
/// The concurrency pattern is Swim's (`Apps/Swim/Sources/SwimSession.swift`,
/// explained in SWIM.md): `@MainActor @Observable`, every delegate method
/// `nonisolated`, and only Sendable values crossing the hop back.
@MainActor @Observable final class WatchLink: NSObject {
    private(set) var activated = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let activated = activationState == .activated
        Task { @MainActor in self.activated = activated }
    }
}
