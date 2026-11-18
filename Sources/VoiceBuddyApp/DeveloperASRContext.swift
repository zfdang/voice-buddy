import Foundation

/// Curated Qwen3-ASR contextual biasing dictionary for developer dictation.
///
/// Organizes 120 high-signal engineering terms across Git/GitHub workflows,
/// Apple/macOS/Swift distribution, languages/frontend, infra/protocols, and AI tooling.
enum DeveloperASRContext {
    static let gitAndWorkflowTerms: [String] = [
        // Git 核心命令与引用
        "Git", "GitHub", "GitLab", "commit", "rebase", "squash", "cherry-pick",
        "stash", "checkout", "reflog", "bisect", "worktree", "submodule",
        "blame", "fetch", "upstream", "origin", "HEAD", "main", "master",
        "gitignore", "pre-commit",
        // GitHub 协作与发布流
        "PR", "Pull Request", "MR", "Merge Request", "fork", "issue",
        "milestone", "webhook", "GitHub Actions", "workflow", "CI/CD",
        "hotfix", "release", "changelog", "SemVer", "LGTM", "Dependabot", "Codespaces"
    ]

    static let appleAndMacOSTerms: [String] = [
        "macOS", "iOS", "Xcode", "Swift", "SwiftUI", "SwiftPM", "AppKit",
        "CoreML", "MLX", "Metal", "arm64", "codesign", "notarization",
        "TestFlight", "Sparkle", "appcast", "CocoaPods", "Homebrew",
        "Info.plist", "xcconfig"
    ]

    static let languagesAndFrontendTerms: [String] = [
        "Python", "TypeScript", "JavaScript", "Golang", "Rust", "React",
        "Vue", "Next.js", "Node.js", "Vite", "Tailwind", "npm", "pnpm", "Cargo"
    ]

    static let infraAndProtocolsTerms: [String] = [
        "Docker", "Kubernetes", "K8s", "Terraform", "Nginx", "Redis",
        "PostgreSQL", "SQLite", "Kafka", "GraphQL", "gRPC", "Protobuf",
        "WebSocket", "API", "SDK", "CLI", "JSON", "YAML", "TOML", "SQL",
        "JWT", "OAuth", "SSH", "TLS", "UUID", "cron"
    ]

    static let aiAndToolingTerms: [String] = [
        "LLM", "ASR", "TTS", "VAD", "RAG", "MCP", "Qwen", "Whisper",
        "SenseVoice", "PyTorch", "Ollama", "vLLM", "LoRA", "HuggingFace",
        "OpenAI", "Claude", "Gemini", "Cursor", "Codex", "VoiceBuddy"
    ]

    static let allTerms: [String] =
        gitAndWorkflowTerms
            + appleAndMacOSTerms
            + languagesAndFrontendTerms
            + infraAndProtocolsTerms
            + aiAndToolingTerms

    static let contextPrompt: String = allTerms.joined(separator: ", ")

    static var terms: [String] { allTerms }
    static var contextString: String { contextPrompt }

    static func context(enabled: Bool) -> String? {
        enabled ? contextPrompt : nil
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
