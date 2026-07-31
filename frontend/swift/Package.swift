// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceForgeMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceForgeMenu",
            path: "Sources/VoiceForgeMenu"
        )
    ]
)
