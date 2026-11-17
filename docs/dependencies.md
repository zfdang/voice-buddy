# 依赖检查（2026-11-17）

检查范围：`Package.swift` 的 5 个直接依赖及 `Package.resolved` 中全部 44 个依赖。通过上游 GitHub Releases / 稳定版本标签核对，并运行 `swift package update` 更新允许范围内的版本。下表版本是本次检查快照，不代表未来的最新版。

## 本次升级

- KeyboardShortcuts：1.17.0 → 3.1.0；将快捷键名称初始化参数 `default:` 迁移为 `initial:`，保持持久化名称 `toggleDictation` 不变。
- swift-jinja：3.1.0 → 3.2.0。
- swift-system：1.8.1 → 1.9.0。
- LaunchAtLogin 5.0.2、Sparkle 2.10.1、ChineseITN 0.3.0 已是最新稳定版本；同步提高前两者的最低依赖要求。
- KeyboardShortcuts 3.1.0 要求 Swift 6.2，源码构建要求更新为 Xcode 26+。

## 完整清单

| 依赖 | 当前锁定 | 最新稳定标签 / 发布 | 说明 |
| :--- | :--- | :--- | :--- |
| [async-http-client](https://github.com/swift-server/async-http-client) | 1.37.0 | 1.37.0 | 已是最新稳定版。 |
| [chinese-itn-swift](https://github.com/xzjh/chinese-itn-swift) | 0.3.0 | 0.3.0 | 已是最新稳定版。 |
| [compress-nio](https://github.com/adam-fowler/compress-nio) | 1.5.0 | 1.5.0 | 已是最新稳定版。 |
| [eventsource](https://github.com/mattt/eventsource) | 1.6.0 | 1.6.0 | 已是最新稳定版。 |
| [hummingbird](https://github.com/hummingbird-project/hummingbird) | 2.16.0 | 2.28.1 | speech-swift 限制为 >=2.5.0、<2.17.0。 |
| [hummingbird-websocket](https://github.com/hummingbird-project/hummingbird-websocket) | 2.6.0 | 2.8.1 | speech-swift 限制为 >=2.6.0、<2.7.0。 |
| [keyboardshortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 3.1.0 | 3.1.0 | 已是最新稳定版。 |
| [launchatlogin](https://github.com/sindresorhus/LaunchAtLogin) | 5.0.2 | 5.0.2 | 已是最新稳定版。 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.4 | 0.33.0 | mlx-swift-lm 3.31.4 限制在 0.31.x。需要在语音引擎 fork 中配套升级并验证推理。 |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 3.31.4 | 3.32.3 | speech-swift 精确固定 3.31.4。 |
| [sparkle](https://github.com/sparkle-project/Sparkle) | 2.10.1 | 2.10.1 | 已是最新稳定版。 |
| [speech-swift](https://github.com/zfdang/speech-swift) | d4b9b9a6 | 0.0.29 | 保留固定提交 d4b9b9a。最新标签 v0.0.29 比当前提交少 38 个提交；fork 的 main 也比当前提交少两个提交，不能用标签或 main 替换项目专用修复。 |
| [swift-algorithms](https://github.com/apple/swift-algorithms) | 1.2.1 | 1.2.1 | 已是最新稳定版。 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.8.2 | 1.8.2 | 已是最新稳定版。 |
| [swift-asn1](https://github.com/apple/swift-asn1) | 1.7.4 | 1.7.4 | 已是最新稳定版。 |
| [swift-async-algorithms](https://github.com/apple/swift-async-algorithms) | 1.1.7 | 1.1.7 | 已是最新稳定版。 |
| [swift-atomics](https://github.com/apple/swift-atomics) | 1.3.1 | 1.3.1 | 已是最新稳定版。 |
| [swift-certificates](https://github.com/apple/swift-certificates) | 1.21.1 | 1.21.1 | 已是最新稳定版。 |
| [swift-collections](https://github.com/apple/swift-collections) | 1.7.6 | 1.7.6 | 已是最新稳定版。 |
| [swift-configuration](https://github.com/apple/swift-configuration) | 1.5.0 | 1.5.0 | 已是最新稳定版。 |
| [swift-crypto](https://github.com/apple/swift-crypto) | 4.5.2 | 5.1.1 | swift-huggingface 1.0.0 限制为 <5.0.0。 |
| [swift-distributed-tracing](https://github.com/apple/swift-distributed-tracing) | 1.7.4 | 1.7.4 | 已是最新稳定版。 |
| [swift-http-structured-headers](https://github.com/apple/swift-http-structured-headers) | 1.7.0 | 1.7.0 | 已是最新稳定版。 |
| [swift-http-types](https://github.com/apple/swift-http-types) | 1.8.0 | 1.8.0 | 已是最新稳定版。 |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | 1.0.0 | 1.0.0 | 已是最新稳定版。 |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | 3.2.0 | 3.2.0 | 已是最新稳定版。 |
| [swift-log](https://github.com/apple/swift-log) | 1.17.0 | 1.17.0 | 已是最新稳定版。 |
| [swift-metrics](https://github.com/apple/swift-metrics) | 2.13.0 | 2.13.0 | 已是最新稳定版。 |
| [swift-nio](https://github.com/apple/swift-nio) | 2.105.0 | 2.105.0 | 已是最新稳定版。 |
| [swift-nio-extras](https://github.com/apple/swift-nio-extras) | 1.35.2 | 1.35.2 | 已是最新稳定版。 |
| [swift-nio-http2](https://github.com/apple/swift-nio-http2) | 1.46.0 | 1.46.0 | 已是最新稳定版。 |
| [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) | 2.37.6 | 2.37.6 | 已是最新稳定版。 |
| [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services) | 1.28.0 | 1.28.0 | 已是最新稳定版。 |
| [swift-numerics](https://github.com/apple/swift-numerics) | 1.1.1 | 1.1.1 | 已是最新稳定版。 |
| [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) | 0.12.1 | 0.12.1 | 已是最新稳定版。 |
| [swift-service-context](https://github.com/apple/swift-service-context) | 1.5.1 | 1.5.1 | 已是最新稳定版。 |
| [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) | 2.13.0 | 2.13.0 | 已是最新稳定版。 |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | 603.0.2 | 604.0.0 | mlx-swift-lm 限制为 >=602.0.0、<604.0.0。 |
| [swift-system](https://github.com/apple/swift-system) | 1.9.0 | 1.9.0 | 已是最新稳定版。 |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 1.4.0 | 1.4.0 | 已是最新稳定版。 |
| [swift-websocket](https://github.com/hummingbird-project/swift-websocket) | 1.5.0 | 1.6.2 | speech-swift 限制为 1.5.x；其注释记录 1.6.0 缺失 NIOSSL 目标依赖，解除限制前需复核后续修复。 |
| [whisperkit](https://github.com/argmaxinc/WhisperKit) | 1.1.1 | 1.1.1 | 已是最新稳定版。 |
| [xgrammar](https://github.com/mlc-ai/xgrammar) | 0.2.7 | 0.2.9 | speech-swift 精确固定 0.2.7，语法引擎变动需要单独验证。 |
| [yyjson](https://github.com/ibireme/yyjson) | 0.13.0 | 0.13.0 | 已是最新稳定版。 |

## 更新边界

未直接修改语音引擎 fork 或覆盖其间接依赖约束。MLX、模型运行时与语法引擎的更新需要在 fork 中配套处理，再用新的固定提交引入。SwiftPM 保持锁文件，避免构建时自动跟踪浮动分支。

KeyboardShortcuts 的 [3.1.0 发布说明](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0)包含 macOS 27 兼容性改进；这不能代替原故障机器上的崩溃报告比对和新包回归验证。

日后更新时先核对发布说明与版本要求，运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift package update`，审查锁文件、执行测试及应用打包。CI 继续仅按既有手动／标签规则触发。

## 本地验证

- Xcode 26.3 / Swift 6.2.4。
- `swift test -j 4`：97 项测试，6 项按条件跳过，零失败。跳过项需要麦克风或真实模型显式启用。
- `scripts/build-app.sh release -s - --allow-adhoc`：Release 编译、Metal 库构建、本地应用签名校验和启动冒烟检查均通过。
- 尚未在原反馈者的 macOS 27.3 机器上验证；不能据此宣称原启动崩溃已经解决。
