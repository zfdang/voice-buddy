# 开源语音输入方案调研

调研日期：2026-11-05。以下来自各项目公开仓库和 README，属于作者对功能的描述；尚未安装、实测或审计源码，功能、许可证和版本可能变化。本文不改变首期应用内 Swift/MLX 加载 Qwen 模型的方向。

**后续源码核查修正**：MacWispr 的 README 仍描述 Qwen 模型选择，但固定提交 `07e514f` 的当前产品目录仅列出 Parakeet Redux。Qwen 后端代码仍保留，不能视为当前可选产品功能。详见 [MacWispr 技术调研](macwispr-technical-review.md)。

## 项目对比

| 项目 | 方案与许可 | 值得参考 | 与 Voice Buddy 的关系 |
| --- | --- | --- | --- |
| [MacWispr](https://github.com/vasanthsreeram/macwispr) | macOS，Swift，MIT；Qwen 0.6B/1.7B 经 MLX 本地运行，也支持云端；本地整理在 beta 版本。 | 同类 Qwen3-ASR 接入、模型按内存推荐、热键、系统插入、声音提示，以及延迟/WER 基准工具。项目提及构建时 Metal 工具和运行时 metallib，值得核对打包过程。 | **优先深入研究**：与首期 ASR 最接近。其型号选择阈值和性能结果不是我们的承诺；云端、遥测及默认历史也不直接沿用。 |
| [VoxLocal](https://github.com/romarayt/VoxLocal) | macOS，MIT；whisper.cpp + 可选本机 Ollama。 | 设置中的麦克风、识别语言、界面语言、热键冲突、本机服务探测；浮窗覆盖完整状态且不抢焦点；缺权限时有手动粘贴路径。 | **优先对照交互和异常恢复**。它描述的插入顺序为 AX 优先、剪贴板后备；我们需实测插入与 Undo，不预设哪种对所有应用更好。 |
| [Handy](https://github.com/cjpais/Handy) | MIT，跨 macOS、Windows、Linux；本地 Whisper/Parakeet，Silero VAD。 | 同时提供按住和切换录音；VAD 过滤静音；模型切换和跨平台结构可以作为以后 Windows 工作的参考。 | **优先研究 VAD 边界与平台抽象**；其模型和性能不能直接推断 Qwen 的表现。 |
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr) | MIT，Electron 跨平台；支持本地与云端。 | 跨平台输入、模型适配和非标准 ASR 接口的 shim；可用于梳理后续 Windows 的接口边界。 | 功能范围较大，适合局部对照；其云端、会议和分享能力不是首期范围。 |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | 原生 macOS，Swift，GPL-3.0；whisper.cpp + FluidAudio + 可选云端 API。 | 完备的应用场景模式（Context-Aware Modes / Profiles）、专有词典与纠错自学习、历史搜索、听写与 AI 助手双模态。详见 [VoiceInk 技术调研与后续演进方向](voiceink-technical-review.md)。 | **核心进阶功能参考标杆**。其应用级规则、用户词典与本地历史归档为 Voice Buddy P1/P2 阶段的核心规划输入；代码复用须评估 GPL 兼容性。 |
| [Voicetypr](https://github.com/ideaplexa/voicetypr) | Rust + Tauri，跨 macOS、Windows；本地 Whisper/ONNX + 可选云端。 | 本地 CLI 与 Agent API 交互、音视频文件本地拖拽转文字、面向开发者（Vibe Coding）的代码/Prompt 格式化规则。详见 [Voicetypr 技术调研与功能借鉴分析](voicetypr-technical-review.md)。 | **开发者工具与接口生态标杆**。其 CLI 命令行能力、Agent Socket 接口及长音频文件转录为 Voice Buddy P2/P3 阶段的重要输入。 |

许可证只描述仓库主项目，模型权重、依赖、构建产物和商标需分别核查。MIT 也要求保留适用的版权与许可声明；不要直接复制代码而不检查具体文件和版本。仓库的隐私声明不能替代我们对版本、模型和网络行为的验证。

## 对首期设计的具体启发

1. **先验证原生 MLX 接入的可行性**：对照 MacWispr 的 Swift/MLX 包装与 Metal 资源打包，与已有 video-auto-translate 的 Python sidecar 比较干净安装、模型复用、内存、冷启动和故障恢复。首期以 Qwen3-ASR 0.6B 为默认候选，1.7B 为进阶候选；比较结果决定是否调整实现，不能直接把示例仓库当依赖引入。
2. **完整状态与恢复**：借鉴 VoxLocal 的不抢焦点浮窗、录音/处理/插入/失败状态、麦克风选择与快捷键冲突提示。模型或 Ollama 失败时保留识别原文，提供明确的用户选择；安全目标变化时不自动粘贴。原文回退、手动复制与是否保存历史需符合本项目已定的隐私和确认规则。
3. **VAD 实验而非照搬阈值**：Handy 使用 Silero VAD，验证它在中文、英文、法语、混说、低声、静音及噪声中的漏检与误检，保留语音两端余量；同时测延迟和资源。参考实现不证明 Qwen 下同样有效。
4. **剪贴板与撤销单独做兼容性实验**：对照 AX 插入、模拟粘贴、手动复制；检测焦点变化、撤销、复制竞争与慢目标。剪贴板隐私标记依赖第三方遵守，不能保证不留痕。不同项目的默认插入顺序只是测试候选。
5. **模型管理面向真实能力**：显示服务运行、模型已安装和模型已加载等不同状态；首期 Qwen ASR 与 Ollama 分别检测，模型缺失时给出指引。保留手动选择，避免硬件检测或服务发现覆盖用户选择。
6. **功能保持聚焦**：应用级规则、词典、选中文本编辑、会议、云同步等先记为候选；首期优先验证离线听写、中文混说、整理可信度与跨应用插入。

## 建议验证顺序

1. 固定每个参考仓库的版本后阅读 MacWispr 的模型加载、音频管道、打包与快捷键实现；明确其 Swift 运行时与当前 sidecar 的依赖、许可和失败边界。
2. 在不采集个人内容的测试环境对照 Handy 的 VAD 和 VoxLocal 的权限、焦点、插入与恢复方案；对原生应用、浏览器、Electron、终端及安全字段逐项记录结果。
3. 使用同一组经授权音频、同一设备和冷/热条件，测 Qwen 识别质量、弱音截断、静音幻觉、停止到上屏时间、内存与电量；再测整理事实保持。公开 benchmark 仅用于选取实验方法，不直接作为验收结果。
4. 做网络断连、服务重启、端口冲突、恶意或异常本机服务、剪贴板历史工具和用户复制竞争测试；不把 localhost 等同于可信服务。

上述是基于仓库公开资料的研究结论，未引入第三方代码，也未修改首期模型选择。
