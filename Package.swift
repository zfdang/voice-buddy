// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceBuddy",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "VoiceBuddy", targets: ["VoiceBuddyApp"])],
    dependencies: [
        .package(url: "https://github.com/zfdang/speech-swift.git", revision: "d4b9b9a67863bafcf60e37e06e6ffcb324a53407"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin.git", from: "5.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "1.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        .target(name: "VoiceBuddyCore"),
        .executableTarget(
            name: "VoiceBuddyApp",
            dependencies: [
                "VoiceBuddyCore",
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "WhisperASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "Qwen3Chat", package: "speech-swift"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: ["Resources"]
        ),
        .testTarget(name: "VoiceBuddyCoreTests", dependencies: ["VoiceBuddyCore", .product(name: "Qwen3ASR", package: "speech-swift"), .product(name: "SpeechVAD", package: "speech-swift"), .product(name: "Qwen3Chat", package: "speech-swift")]),
        .testTarget(name: "VoiceBuddyAppTests", dependencies: ["VoiceBuddyApp"])
    ]
)
