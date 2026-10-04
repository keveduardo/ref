import CoreLocation
import Foundation
import Observation
import RefKit

/// The route behind the distance number.
///
/// Deliberately no `allowsBackgroundLocationUpdates`: it terminates an app
/// that has not declared the `location` background mode, and an active workout
/// session already keeps us alive on the pitch. The accuracy filtering and the
/// metres themselves are pure RefKit (`GeoDistance`), tested on Linux — this
/// class only owns the manager and the authorization.
@MainActor @Observable final class LocationRecorder: NSObject {
    private let manager = CLLocationManager()
    private var points: [RoutePoint] = []
    private(set) var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    /// Asked once, before a match — a system prompt mid-match is a disaster.
    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        points = []
        running = true
        manager.startUpdatingLocation()
    }

    /// Full time. Returns the distance in metres, or nil when there were too
    /// few trustworthy fixes — the report then shows "—", and the match is
    /// unaffected.
    func stop() -> Double? {
        running = false
        manager.stopUpdatingLocation()
        let filtered = GeoDistance.filtered(points)
        guard filtered.count > 1 else { return nil }
        return GeoDistance.metres(filtered)
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        // CLLocation is not Sendable; RoutePoint is, so the hop is clean.
        let converted = locations.map {
            RoutePoint(latitude: $0.coordinate.latitude,
                       longitude: $0.coordinate.longitude,
                       accuracy: $0.horizontalAccuracy,
                       at: $0.timestamp)
        }
        Task { @MainActor in self.points.append(contentsOf: converted) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
