// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The code shared with sNotate and sCapture: the sibling checkout when there
// is one, else the published package (DECISIONS 2026-10-30).
let sibling = URL(fileURLWithPath: Context.packageDirectory)
    .deletingLastPathComponent()
    .appendingPathComponent("scommon/Package.swift")
let scommon: Package.Dependency = FileManager.default.fileExists(atPath: sibling.path)
    ? .package(path: "../scommon")
    : .package(
        url: "https://github.com/uSuite/scommon.git",
        from: "0.3.0"
    )

let package = Package(
    name: "sView",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "SViewCore",
            targets: ["SViewCore"]
        ),
        .executable(
            name: "sView",
            targets: ["sView"]
        ),
        .executable(
            name: "sview-cheatsheet",
            targets: ["sview-cheatsheet"]
        ),
    ],
    dependencies: [
        scommon
    ],
    targets: [
        .target(
            name: "SViewCore",
            dependencies: [
                .product(
                    name: "SCommon",
                    package: "scommon"
                )
            ]
        ),
        .executableTarget(
            name: "sView",
            dependencies: ["SViewCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "sview-cheatsheet",
            dependencies: ["SViewCore"]
        ),
        .testTarget(
            name: "SViewCoreTests",
            dependencies: ["SViewCore"]
        ),
    ]
)
