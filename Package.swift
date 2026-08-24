// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoiceCrush",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "VoiceCrush", targets: ["VoiceCrush"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceCrush",
            path: "Sources/VoiceCrush",
            exclude: [
                "Info.plist",
                "VoiceCrush.entitlements"
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
