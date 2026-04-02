// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "sidereal-beacon",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SiderealBeacon", targets: ["SiderealBeacon"]),
    ],
    targets: [
        .target(
            name: "SiderealBeacon",
            path: "Sources/SiderealBeacon"
        ),
        .testTarget(
            name: "SiderealBeaconTests",
            dependencies: ["SiderealBeacon"],
            path: "Tests/SiderealBeaconTests"
        ),
    ]
)
