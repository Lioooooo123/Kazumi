// swift-tools-version:5.9
// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import PackageDescription

let package = Package(
    name: "KazumiNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KazumiCore", targets: ["KazumiCore"]),
        .library(name: "MPVBridge", targets: ["MPVBridge"]),
    ],
    targets: [
        .target(name: "MPVBridge", publicHeadersPath: "include"),
        .target(
            name: "KazumiCore",
            path: "Sources/KazumiCore",
            linkerSettings: [
                .linkedLibrary("iconv", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "KazumiCoreTests",
            dependencies: ["KazumiCore"],
            path: "Tests/KazumiCoreTests"
        ),
    ]
)
