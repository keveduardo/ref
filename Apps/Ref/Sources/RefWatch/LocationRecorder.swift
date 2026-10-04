import CoreLocation
import Foundation
import Observation

/// The route behind the distance number. P0: the manager and its delegate
/// compile; nothing starts one. P4 asks for authorisation *before* kick-off —
/// a system prompt mid-match is a disaster — and sums filtered points with the
/// pure maths in RefKit.
///
/// Deliberately no `allowsBackgroundLocationUpdates`: it terminates an app
/// that has not declared the `location` background mode, and an active workout
/// session already keeps us alive on the pitch.
@MainActor @Observable final class LocationRecorder: NSObject {
    private let manager = CLLocationManager()
    private(set) var fixes = 0

    override init() {
        super.init()
        manager.delegate = self
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        // CLLocation is not Sendable; only the scalar crosses the hop.
        let count = locations.count
        Task { @MainActor in self.fixes += count }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
