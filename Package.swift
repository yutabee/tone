// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToneCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ToneCore", targets: ["ToneCore"]),
    ],
    targets: [
        .target(name: "ToneCore"),
        .testTarget(
            name: "ToneCoreTests",
            dependencies: ["ToneCore"]
        ),
    ]
)
