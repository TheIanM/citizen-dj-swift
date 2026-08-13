// swift-tools-version: 5.9
import PackageDescription

/// CitizenDJ — a native Swift drum-loop generator ported from the Library of Congress
/// "Citizen DJ" web app. Generates evolving 16-step drum loops on-device from the
/// project's bundled drum-machine samples and hand-authored patterns.
let package = Package(
    name: "CitizenDJ",
    platforms: [
        // iOS is the primary target (the WILDxCARD game). macOS is declared so the
        // package also builds/tests on a Mac dev machine using AVFoundation + offline rendering.
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CitizenDJ", targets: ["CitizenDJ"])
    ],
    targets: [
        // Bundled resources: the Roland TR-808 one-shot samples (~27 mp3s) and the two
        // drum-data JSONs. These are staged under Sources/CitizenDJ/Resources/ by
        // `scripts/sync-resources.sh`. MVP scope is 808-only, so just that machine's hits
        // are copied (not all 8 machines / 212 samples).
        .target(
            name: "CitizenDJ",
            dependencies: [],
            resources: [
                .copy("Resources/audio"),
                .copy("Resources/data")
            ]
        ),
        .testTarget(name: "CitizenDJTests", dependencies: ["CitizenDJ"]),

        // Tiny CLI to bounce an evolving loop to a WAV so you can listen to the generator.
        // Usage: `swift run citizen-dj-demo [bars] [outputPath]`
        .executableTarget(name: "citizen-dj-demo", dependencies: ["CitizenDJ"])
    ]
)
