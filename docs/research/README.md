# 第三方开源项目技术研究与源码分析 (Third-Party Project Research)

本目录集中存放针对具体开源语音输入/听写软件的深入源码分析、架构拆解与技术借鉴报告。

---

## 目录索引

| 项目名称 | 技术栈 | 核心特色 | 深度调研报告 |
| :--- | :--- | :--- | :--- |
| **MacWispr** | Swift + MLX (macOS) | Qwen3-ASR 本地加载、Metal 着色器打包、Silero VAD | [`macwispr.md`](./macwispr.md) |
| **VoiceInk** | Swift + AppKit (macOS) | 场景感知应用模式、专有词库自学习、可检索历史看板 | [`voiceink.md`](./voiceink.md) |
| **Voicetypr** | Rust + Tauri (跨平台) | 本地 CLI 命令行、Agent API 接口、音视频长文件转录 | [`voicetypr.md`](./voicetypr.md) |

---

## 全景与顶层参考
关于行业整体标杆对比、底层声学推理引擎（SenseVoice / WhisperKit / sherpa-onnx）及 Voice Buddy 完整路线图规划，请参阅顶层文档：
- [核心参考项目与行业标杆全景调研 (`docs/references.md`)](../references.md)
