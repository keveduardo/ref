import Foundation
import Testing
@testable import RefKit

@Suite("kilometres or miles")
struct DistanceUnitTests {
    @Test func distances() {
        #expect(DistanceUnit.kilometres.format(metres: 1_700) == "1.7 km")
        #expect(DistanceUnit.miles.format(metres: 1_700) == "1.1 mi")
        #expect(DistanceUnit.miles.format(metres: 1_609.344, decimals: 2) == "1.00 mi")
    }

    @Test func speeds() {
        // 25 km/h.
        #expect(DistanceUnit.kilometres.formatSpeed(metresPerSecond: 25 / 3.6) == "25.0 km/h")
        #expect(DistanceUnit.miles.formatSpeed(metresPerSecond: 25 / 3.6) == "15.5 mph")
    }

    @Test func theRegionDecidesUntilTheRefereePicks() {
        #expect(DistanceUnit.default(for: Locale(identifier: "en_US")) == .miles)
        #expect(DistanceUnit.default(for: Locale(identifier: "es_MX")) == .kilometres)
    }

    @Test func theSharedReportUsesTheChoice() {
        var match = Fixture.playedMatch()
        match.metrics?.distanceMeters = 8_046.72 // 5 miles
        #expect(match.report.shareText(match: match, unit: .miles).contains("Distance 5.0 mi."))
        #expect(match.report.shareText(match: match).contains("Distance 8.0 km."))
    }
}
