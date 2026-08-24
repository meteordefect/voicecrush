// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoicePilot",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "VoicePilot", targets: ["VoicePilot"])
    ],
    targets: [
        .executableTarget(
            name: "VoicePilot",
            path: "Sources/VoicePilot",
            exclude: [
                "Info.plist",
                "VoicePilot.entitlements"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        )
    ]
)
