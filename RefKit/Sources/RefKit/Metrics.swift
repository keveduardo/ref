import Foundation

/// One GPS fix, reduced to what the distance maths needs. `CLLocation` is a
/// class and not Sendable; the watch's recorder converts to this at the
/// boundary, and everything downstream is pure.
public struct RoutePoint: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// `horizontalAccuracy`, in metres.
    public var accuracy: Double
    public var at: Date

    public init(latitude: Double, longitude: Double, accuracy: Double, at: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.at = at
    }
}

/// The distance behind the report's number — pure, so it is tested on Linux
/// and never depends on a run outdoors.
public enum GeoDistance {
    /// Drop fixes too inaccurate to trust. A referee under trees or beside a
    /// stand produces plenty of these; left in, they invent distance.
    public static func filtered(_ points: [RoutePoint], maxAccuracy: Double = 30) -> [RoutePoint] {
        points.filter { $0.accuracy > 0 && $0.accuracy <= maxAccuracy }
    }

    /// Metres over consecutive fixes, haversine. Leap-sized gaps — a lost
    /// signal, a walk to the car — are someone else's problem to filter;
    /// this is arithmetic, not judgement.
    public static func metres(_ points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for (a, b) in zip(points, points.dropFirst()) {
            total += haversineMetres(a, b)
        }
        return total
    }

    static func haversineMetres(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}

/// What the workout cost — frozen into the match record at full time, so the
/// phone can show it without any Health permission of its own. The route
/// itself stays on the watch in v1 (a 90-minute route is far past a
/// comfortable WatchConnectivity payload); only the number travels.
public struct MatchMetrics: Codable, Sendable, Equatable {
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var activeCalories: Double?
    /// Steps during the match. Optional like the rest, so a record from a
    /// build before steps were counted still decodes.
    public var steps: Int?
    /// The `HKWorkout`'s UUID, so the phone can find the workout in Health
    /// later (charts, a share sheet) without guessing by date.
    public var workoutUUID: String?

    public init(distanceMeters: Double? = nil, averageHeartRate: Double? = nil,
                maxHeartRate: Double? = nil, activeCalories: Double? = nil,
                steps: Int? = nil, workoutUUID: String? = nil) {
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeCalories = activeCalories
        self.steps = steps
        self.workoutUUID = workoutUUID
    }
}
