import Foundation

/// Kilometres or miles, the referee's choice in Settings (Kevin, 2026-11-12:
/// "an option to choose kilometers or miles in the settings"). Distances are
/// stored in metres whatever is chosen; this is only how they are read.
public enum DistanceUnit: String, Codable, Sendable, CaseIterable {
    case kilometres, miles

    /// Miles where the phone's region measures in them (the US, the UK…),
    /// kilometres elsewhere — until the referee picks.
    public static func `default`(for locale: Locale = .current) -> DistanceUnit {
        switch locale.measurementSystem {
        case .us, .uk: .miles
        default: .kilometres
        }
    }

    public var title: String { self == .kilometres ? "Kilometres" : "Miles" }
    public var symbol: String { self == .kilometres ? "km" : "mi" }
    public var speedSymbol: String { self == .kilometres ? "km/h" : "mph" }

    static let metresPerMile = 1609.344

    /// Metres → the chosen unit.
    public func value(metres: Double) -> Double {
        self == .kilometres ? metres / 1000 : metres / Self.metresPerMile
    }

    /// "1.7 km", "1.1 mi".
    public func format(metres: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f \(symbol)", value(metres: metres))
    }

    /// Metres a second → "24.5 km/h", "15.2 mph".
    public func formatSpeed(metresPerSecond: Double) -> String {
        String(format: "%.1f \(speedSymbol)", value(metres: metresPerSecond * 3600))
    }

    /// The sprint threshold, 20 km/h, as this unit says it: "20 km/h", "12 mph".
    public var sprintThreshold: String {
        self == .kilometres ? "20 km/h" : "12 mph"
    }
}
