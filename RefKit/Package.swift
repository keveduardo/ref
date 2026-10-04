// swift-tools-version: 6.0

import PackageDescription

// The ref kit: everything a referee's match *is* — the clock, the incident
// log, the score, the sin bins, the report — with no SwiftUI, no HealthKit and
// no WatchConnectivity anywhere near it.
//
// **Why this is its own package.** The same split as RowingKit and SwimKit:
// everything that is arithmetic lives here, where `swift test` runs on kevg10,
// and the two apps keep only what needs a screen, a sensor or a radio — which
// only the macOS runner can compile. Nothing here imports anything but
// Foundation. See SCOPE.md.
let package = Package(
    name: "RefKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "RefKit", targets: ["RefKit"]),
    ],
    targets: [
        .target(name: "RefKit"),
        .testTarget(name: "RefKitTests", dependencies: ["RefKit"]),
    ]
)
