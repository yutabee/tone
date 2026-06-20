// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tone",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ToneCore", targets: ["ToneCore"]),
        .library(name: "ToneAudio", targets: ["ToneAudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.6.0"),
        .package(url: "https://github.com/AudioKit/SoundpipeAudioKit.git", from: "5.6.0"),
    ],
    targets: [
        // ドメイン層: AudioKit / SwiftUI 非依存、macOS で swift test 可能。
        .target(name: "ToneCore"),
        // 実機オーディオ層: iOS 専用。AudioKit/SoundpipeAudioKit は iOS でのみリンク。
        .target(
            name: "ToneAudio",
            dependencies: [
                "ToneCore",
                .product(name: "AudioKit", package: "AudioKit", condition: .when(platforms: [.iOS])),
                .product(name: "SoundpipeAudioKit", package: "SoundpipeAudioKit", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "ToneCoreTests", dependencies: ["ToneCore"]),
    ]
)
