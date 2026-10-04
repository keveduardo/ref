import Foundation
import Observation
import WatchConnectivity

/// The phone's half of the link to the watch. P0: activation and the delegate
/// conformances only — the assignment going out and the finished match coming
/// back arrive with the sync work (P4).
///
/// The concurrency pattern is Swim's (`Apps/Swim/Sources/SwimSession.swift`,
/// explained in SWIM.md): `@MainActor @Observable`, every delegate method
/// `nonisolated`, and only Sendable values crossing the hop back.
@MainActor @Observable final class PhoneLink: NSObject {
    private(set) var activated = false

    var status: String { activated ? "Connected" : "Not activated" }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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
        // silently stops receiving. (P4 is where it starts to matter.)
        WCSession.default.activate()
    }
    #endif
}
