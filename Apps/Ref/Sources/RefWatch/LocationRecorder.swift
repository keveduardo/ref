import CoreLocation
import Foundation
import Observation
import RefKit

/// The route behind the distance number and the pitch diagram, and the
/// compass behind "Mark field".
///
/// Deliberately no `allowsBackgroundLocationUpdates`: it terminates an app
/// that has not declared the `location` background mode, and an active workout
/// session already keeps us alive on the pitch. The accuracy filtering, the
/// metres and the pitch maths are pure RefKit (`GeoDistance`, `PitchFrame`,
/// `MovementReport`), tested on Linux — this class only owns the manager and
/// the authorization.
@MainActor @Observable final class LocationRecorder: NSObject {
    private let manager = CLLocationManager()
    private(set) var points: [RoutePoint] = []
    private(set) var running = false
    /// The newest fix and compass reading — what "Mark field" captures.
    private(set) var latestFix: RoutePoint?
    private(set) var latestHeading: Double?

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

    /// GPS and compass on, for marking the field before kick-off. Nothing is
    /// added to the route until `start()`.
    func warmUp() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    var compassAvailable: Bool { CLLocationManager.headingAvailable() }

    /// Kick-off: the route starts here.
    func start() {
        points = []
        running = true
        manager.stopUpdatingHeading()
        manager.startUpdatingLocation()
    }

    /// Full time. Returns the distance in metres, or nil when there were too
    /// few trustworthy fixes — the report then shows "—", and the match is
    /// unaffected. The route stays in `points` for the pitch diagram.
    func stop() -> Double? {
        running = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        let filtered = GeoDistance.filtered(points)
        guard filtered.count > 1 else { return nil }
        return GeoDistance.metres(filtered)
    }

    fileprivate func received(_ converted: [RoutePoint]) {
        if let last = converted.last { latestFix = last }
        if running { points.append(contentsOf: converted) }
    }

    fileprivate func received(heading: Double) {
        latestHeading = heading
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
        Task { @MainActor in self.received(converted) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True north when the watch knows it (it needs a location fix);
        // magnetic otherwise — off by the local declination, ~12° in
        // southern California, which the pitch diagram can live with.
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard degrees >= 0 else { return }
        Task { @MainActor in self.received(heading: degrees) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
