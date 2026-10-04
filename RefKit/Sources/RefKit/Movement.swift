import Foundation

/// A field's size in metres, with the penalty area for the drawing.
public struct PitchSize: Codable, Sendable, Equatable {
    public var length: Double
    public var width: Double
    public var penaltyDepth: Double
    public var penaltyWidth: Double

    public init(length: Double, width: Double, penaltyDepth: Double, penaltyWidth: Double) {
        self.length = length
        self.width = width
        self.penaltyDepth = penaltyDepth
        self.penaltyWidth = penaltyWidth
    }

    static func yards(_ length: Double, _ width: Double, penalty depth: Double, _ penaltyWidth: Double) -> PitchSize {
        let metre = 0.9144
        return PitchSize(length: length * metre, width: width * metre,
                         penaltyDepth: depth * metre, penaltyWidth: penaltyWidth * metre)
    }

    /// The full-size game: 105 × 68 m.
    public static let adult = PitchSize(length: 105, width: 68, penaltyDepth: 16.5, penaltyWidth: 40.3)
}

/// Where the field is and which way it lies: the centre spot, and the
/// compass bearing from it toward one goal. Everything on the pitch diagram
/// is measured in this frame — x along the length toward that goal, y across
/// it to the referee's left as they faced it, both in metres from the centre
/// spot.
public struct PitchFrame: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// Degrees clockwise from true north.
    public var bearing: Double
    /// True when the referee stood on the centre spot and marked it; false
    /// when it was worked out from the route afterwards.
    public var marked: Bool

    public init(latitude: Double, longitude: Double, bearing: Double, marked: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.bearing = bearing
        self.marked = marked
    }

    /// Metres east and north of the centre spot — a flat-earth approximation,
    /// off by well under a metre across a soccer field.
    func eastNorth(_ point: RoutePoint) -> (east: Double, north: Double) {
        let metresPerDegree = 111_320.0
        let north = (point.latitude - latitude) * metresPerDegree
        let east = (point.longitude - longitude) * metresPerDegree * cos(latitude * .pi / 180)
        return (east, north)
    }

    /// A route point on the pitch: x toward the goal the bearing points at,
    /// y to the left of that direction.
    public func project(_ point: RoutePoint) -> (x: Double, y: Double) {
        let (east, north) = eastNorth(point)
        let b = bearing * .pi / 180
        // Forward is (sin b, cos b) in (east, north); left is (-cos b, sin b).
        return (east * sin(b) + north * cos(b), -east * cos(b) + north * sin(b))
    }

    /// The inverse of `project`: a spot on the pitch as a GPS point. Used to
    /// build routes for the tests and the screenshot demo.
    public func point(x: Double, y: Double, at date: Date, accuracy: Double = 5) -> RoutePoint {
        let b = bearing * .pi / 180
        let east = x * sin(b) - y * cos(b)
        let north = x * cos(b) + y * sin(b)
        let metresPerDegree = 111_320.0
        return RoutePoint(latitude: latitude + north / metresPerDegree,
                          longitude: longitude + east / (metresPerDegree * cos(latitude * .pi / 180)),
                          accuracy: accuracy, at: date)
    }

    /// The frame worked out from where the referee went: the centre of their
    /// movement, and its long axis. A referee on the diagonal covers more of
    /// the length than the width, so the long axis of the route is the long
    /// axis of the field. Nil with too few points to say.
    public static func inferred(from points: [RoutePoint]) -> PitchFrame? {
        guard points.count >= 10 else { return nil }
        let lat0 = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let lon0 = points.map(\.longitude).reduce(0, +) / Double(points.count)
        let origin = PitchFrame(latitude: lat0, longitude: lon0, bearing: 0, marked: false)
        let xy = points.map { origin.eastNorth($0) }
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in xy {
            sxx += p.east * p.east
            syy += p.north * p.north
            sxy += p.east * p.north
        }
        // The principal axis, as an angle from east toward north…
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        // …as a compass bearing, clockwise from north, in 0..<180 (either
        // end of the field is as good as the other).
        var bearing = 90 - theta * 180 / .pi
        bearing = bearing.truncatingRemainder(dividingBy: 180)
        if bearing < 0 { bearing += 180 }
        return PitchFrame(latitude: lat0, longitude: lon0, bearing: bearing, marked: false)
    }
}

extension PitchFrame {
    /// The frame to draw a match in: the one the referee marked, when they
    /// did; their marked centre with the route's direction, when the watch
    /// had no compass (`marked` false); otherwise the route's own.
    public static func resolve(marked: PitchFrame?, route: [RoutePoint]) -> PitchFrame? {
        if let marked, marked.marked { return marked }
        guard let inferred = inferred(from: GeoDistance.filtered(route)) else { return marked }
        guard let centre = marked else { return inferred }
        return PitchFrame(latitude: centre.latitude, longitude: centre.longitude,
                          bearing: inferred.bearing, marked: false)
    }
}

/// What the route says about how the referee moved — the phone's pitch
/// diagram and the numbers under it. Only the time the clock was running
/// counts: half-time and the walk to the car are not part of the match.
public struct MovementReport: Codable, Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    /// Seconds spent in each cell, row-major. Columns run along the length
    /// (x, from the far end behind the bearing to the end it points at);
    /// rows run across (y, from the right touchline to the left).
    public var heat: [Double]
    /// Metres covered in each half, first half first.
    public var distanceByHalf: [Double]
    /// Metres per second, after smoothing out GPS jitter.
    public var topSpeed: Double
    /// Separate bursts at sprint speed (`sprintSpeed`) lasting 2 s or more.
    public var sprints: Int
    /// Share of the time in each third of the length: the end behind the
    /// bearing, the middle, the end it points at. Sums to 1 (or all 0).
    public var thirds: [Double]
    /// Share of the time within a band around the nearer of the two
    /// diagonals — how closely the referee kept a diagonal system.
    public var onDiagonal: Double
    /// Share of the time more than 5 m outside the field — a sign the frame
    /// is off, or a long walk to a stoppage.
    public var outside: Double

    /// 20 km/h, the common threshold for a sprint in referee studies.
    public static let sprintSpeed = 20 / 3.6

    /// The max of `heat`, for scaling the colours.
    public var hottest: Double { heat.max() ?? 0 }

    public static func make(points: [RoutePoint], frame: PitchFrame, size: PitchSize,
                            clock: MatchClock, columns: Int = 21, rows: Int = 14) -> MovementReport {
        var heat = [Double](repeating: 0, count: columns * rows)
        var distance = [Double](repeating: 0, count: max(1, clock.config.halves))
        var thirds = [0.0, 0.0, 0.0]
        var diagonalTime = 0.0, outsideTime = 0.0, total = 0.0
        var speeds: [(at: Date, speed: Double)] = []

        let route = GeoDistance.filtered(points).sorted { $0.at < $1.at }
        let halfLength = size.length / 2, halfWidth = size.width / 2
        let band = size.width * 0.15
        // Unit vectors along the two diagonals, corner to corner.
        let diagonalLength = (size.length * size.length + size.width * size.width).squareRoot()
        let ux = size.length / diagonalLength, uy = size.width / diagonalLength

        for (a, b) in zip(route, route.dropFirst()) {
            let dt = b.at.timeIntervalSince(a.at)
            guard dt > 0, dt <= 10, clock.phase(at: a.at).isRunning else { continue }
            let half = clock.currentHalf(at: a.at)
            let metres = GeoDistance.haversineMetres(a, b)
            let speed = metres / dt
            // Faster than any human: a GPS jump, not a run.
            guard speed < 10 else { continue }
            if half >= 1, half <= distance.count { distance[half - 1] += metres }
            speeds.append((b.at, speed))

            let p = frame.project(a)
            total += dt
            if abs(p.x) > halfLength + 5 || abs(p.y) > halfWidth + 5 { outsideTime += dt }
            let column = min(columns - 1, max(0, Int((p.x + halfLength) / size.length * Double(columns))))
            let row = min(rows - 1, max(0, Int((p.y + halfWidth) / size.width * Double(rows))))
            heat[row * columns + column] += dt
            let third = min(2, max(0, Int((p.x + halfLength) / size.length * 3)))
            thirds[third] += dt
            // Distance from each diagonal line through the centre spot.
            let toFirst = abs(p.x * uy - p.y * ux)
            let toSecond = abs(p.x * uy + p.y * ux)
            if min(toFirst, toSecond) <= band { diagonalTime += dt }
        }

        // Speed smoothed over three readings, so one jittery fix is not a sprint.
        var smoothed: [(at: Date, speed: Double)] = []
        for i in speeds.indices {
            let window = speeds[max(0, i - 1)...min(speeds.count - 1, i + 1)]
            smoothed.append((speeds[i].at, window.map(\.speed).reduce(0, +) / Double(window.count)))
        }
        var sprints = 0
        var burstStart: Date?
        var counted = false
        for reading in smoothed {
            if reading.speed >= sprintSpeed {
                if burstStart == nil { burstStart = reading.at; counted = false }
                if !counted, let start = burstStart, reading.at.timeIntervalSince(start) >= 2 {
                    sprints += 1
                    counted = true
                }
            } else {
                burstStart = nil
            }
        }

        let share = { (seconds: Double) in total > 0 ? seconds / total : 0 }
        return MovementReport(columns: columns, rows: rows, heat: heat,
                              distanceByHalf: distance,
                              topSpeed: smoothed.map(\.speed).max() ?? 0,
                              sprints: sprints,
                              thirds: thirds.map(share),
                              onDiagonal: share(diagonalTime),
                              outside: share(outsideTime))
    }
}

extension MatchFormat {
    /// The middle of AYSO's recommended field size for the division (AYSO
    /// wiki, "Size of Ball and Field by Age Division"): 10U 55–65 × 35–45 yd,
    /// 12U 70–80 × 45–55 yd, 14U 100–130 × 50–100 yd.
    public var pitch: PitchSize {
        switch playersPerSide {
        case 7: .yards(60, 40, penalty: 12, 24)
        case 9: .yards(75, 50, penalty: 14, 36)
        case 11 where halfMinutes < 45: .yards(110, 70, penalty: 18, 44)
        default: .adult
        }
    }
}
