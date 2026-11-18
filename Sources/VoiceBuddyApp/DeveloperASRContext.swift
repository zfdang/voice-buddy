import Foundation

/// Curated Qwen3-ASR contextual biasing dictionary for developer dictation.
///
/// Kept intentionally compact (high-signal proper nouns and unambiguous engineering
/// acronyms only) to preserve `"auto"` language detection on everyday Chinese speech
/// and avoid inflating decoder prefill latency.
enum DeveloperASRContext {
    static let terms: [String] = [
        // Git & CI/CD
        "Git", "GitHub", "GitLab", "rebase", "squash", "cherry-pick",
        // Apple / macOS / Swift
        "macOS", "Xcode", "Swift", "SwiftUI", "SwiftPM", "AppKit",
        "CoreML", "MLX", "Metal", "arm64", "codesign", "TestFlight", "Sparkle", "appcast",
        // Languages & Frameworks
        "Python", "TypeScript", "JavaScript", "Golang", "Rust",
        "React", "Vite", "Tailwind",
        // Infrastructure, Protocols & Data
        "Docker", "Kubernetes", "Terraform", "Nginx", "Redis", "PostgreSQL", "SQLite", "Kafka",
        "GraphQL", "gRPC", "Protobuf", "WebSocket",
        "API", "SDK", "CLI", "JSON", "YAML", "TOML", "SQL", "JWT", "OAuth", "SSH", "TLS", "UUID",
        // AI / Speech & Developer Tools
        "LLM", "ASR", "TTS", "VAD", "RAG", "MCP",
        "Qwen", "Whisper", "SenseVoice", "PyTorch", "Ollama", "vLLM",
        "OpenAI", "Claude", "Gemini", "Cursor", "Codex", "VoiceBuddy"
    ]

    static let contextString: String = terms.joined(separator: ", ")

    static func context(enabled: Bool) -> String? {
        enabled ? contextString : nil
    }
}

enum Qwen3ASRContextNormalizer {
    static func normalize(_ rawContext: String?) -> String? {
        guard let trimmed = rawContext?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
