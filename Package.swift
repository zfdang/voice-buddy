// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceBuddy",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "VoiceBuddy", targets: ["VoiceBuddyApp"])],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift.git", revision: "a57702e6f523fa36ac5532d2bdc5f35f701a052c"),
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
                .product(name: "Qwen3ASR", package: "speech-swift"),
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
