# MacWispr 技术调研

调研日期：2026-11-05。对象为 [MacWispr](https://github.com/vasanthsreeram/macwispr)，固定主分支提交 [`07e514f`](https://github.com/vasanthsreeram/macwispr/tree/07e514f756202018c83b7f6c487e54755b939b63)（2026-11-03）。本次静态阅读公开源码及 README，未编译、运行、验证性能或完整审计。这里的结论是 Voice Buddy 的设计输入，不代表已实现。

## 最重要的发现：README 与当前代码不一致

README 描述 Qwen 0.6B/1.7B、Parakeet 等选择；但当前 [`ModelCatalog.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/MacWisprCore/ModelCatalog.swift) 只将 Parakeet Redux 列为可选模型，并将旧选择迁移到它。[`AppState.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/AppState.swift) 也将本地整理设为关闭。源码仍保留 Qwen 后端，但 [`ASRModelSize.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/ASRModelSize.swift) 中实际 Qwen 条目为 0.6B，不是我们首期计划的 1.7B。不能把 README 的模型选择当作当前版本的产品行为，更不能当成 Qwen 1.7B 已验证的 Swift 集成。

## 代码与可借鉴之处

### ASR 与模型生命周期

[`TranscriptionEngine.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/TranscriptionEngine.swift) 用 Swift actor 管理 Qwen、Parakeet 等后端，Qwen 通过 `speech-swift` 的 `Qwen3ASRModel.fromPretrained` 加载，并用 1 秒静音、8 token 做预热；模型切换/卸载使用 generation 防止旧异步加载结果覆盖新状态。Qwen 路径还加载 Silero VAD。依赖在 [`Package.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Package.swift) 中引入，`speech-swift` 使用 main 分支；发布产品应锁定具体依赖版本及对应权重、校验许可与更新风险。

对 Voice Buddy：做一项原生 Swift MLX 与既有 `video-auto-translate` Python sidecar 的可行性对照，使用同一 Qwen3-ASR **1.7B 8-bit** 权重、语言、音频、设备和热/冷状态，检查结果一致性、依赖体积、内存、延迟、打包及故障恢复。当前首期优先 Swift/MLX，sidecar 仅作为对照；Swift 路线能否加载相同权重、支持语言提示和用户词汇，须实际验证后决定。预热成本和静音幻觉不能忽略，预热结果绝不能插入。

### 音频和 VAD

[`AudioRecorder.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/AudioRecorder.swift) 用 AVAudioEngine 采集，支持通过 Core Audio UID 指定麦克风，转换为 16 kHz、单声道 float32；RMS 用于界面电平，不是 VAD。优先使用 AVAudioConverter，无法建立时有线性重采样回退；设备找不到时回退系统默认设备。长录音使用环形缓存，并可能将较早 PCM 写盘。后两者不宜直接照搬：Voice Buddy 应提示设备变化，且默认不持久化音频，长录音缓存策略须明确隐私设置。

Qwen 的流式路径使用 Silero VAD，1.5 秒以下或 VAD 不可用时走批处理；超过阈值时使用 8 秒最大片段和 0.9 秒部分结果间隔。**这不是所有输入都经 VAD 静音过滤**：不能据此说该项目满足我们的 P0 静音检测。短句尤其要独立测 VAD 漏字、误判和幻觉；Voice Buddy 保留自己的静音检测要求，不照抄这些阈值。

[`AudioChunkPlanner.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/MacWisprCore/AudioChunkPlanner.swift) 为 Qwen 设计 30 秒窗口、2 秒重叠及 token 预算，再拼接文本。对短句首版不必立即增加复杂分块；长录音需测试中文无空格、重复语句和跨边界遗漏，不能仅依赖英文词重叠拼接。

### 插入、焦点与权限

[`TextInserter.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/TextInserter.swift) 先清空并写入系统剪贴板，再根据辅助功能权限和 `IsSecureEventInputEnabled()` 决定模拟 Cmd+V、逐字输入或只复制。检查事件投递权限与安全输入状态值得参考，但此文件没有恢复原剪贴板、添加 transient/concealed 标记或确认目标已处理粘贴；发送事件后返回 ok 不等于确认插入成功。所读路径未证明开始时目标焦点与结束时一致。安全输入检测也不能证明所有敏感字段都可识别。

因此 Voice Buddy 保持更保守的目标复核、标记、剪贴板所有权与恢复状态机，以及无法确认时的人工恢复；逐字注入须测试 Unicode、终端、撤销、性能与目标改变，不能自动当成安全后备。原项目的“只复制”仍会暴露给剪贴板历史工具，不能等同于无痕。

### 快捷键和提示

[`HotkeyManager.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/HotkeyManager.swift) 组合事件 tap、Carbon 和全局/本地事件监听，合并重复按下/释放，并处理修饰键提前释放。可借鉴状态去重、权限不可用提示和录制快捷键时暂停触发；这不证明单独 Fn 在所有键盘和 macOS 版本上可捕获。首期默认候选改为 ⌥ Space；仍需真机验证系统和应用冲突并支持改键。

### 文本整理

[`TextPolisher.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/TextPolisher.swift) 是内嵌 MLX 路线，并非我们计划的 Ollama；它处理空结果、错误、过长输出及部分模型说明文字，并在失败时返回原文。该版本按空格切词，少于三个词跳过整理，这对不以空格分词的中文不适用。可以参考超时、清理和异常结果的防护思想，但不能把长度检查当作事实正确性验证；Voice Buddy 按整理力度走规则或应用内本地 Qwen，失败时明确提示和保留原文。

### 分发与模型缓存

[`build-app.sh`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/scripts/build-app.sh) 显式编译并随应用放置 `mlx.metallib`，避免缺少 GPU 着色器；模型权重不打包进应用。原生 MLX 原型应测试从干净机器安装的签名、公证、资源路径和离线启动。当前 sidecar 路线也需分别验证 Python、依赖及模型分发，不应假定原生方案天然更简单。

[`ASRModelCache.swift`](https://github.com/vasanthsreeram/macwispr/blob/07e514f756202018c83b7f6c487e54755b939b63/Sources/ASRModelCache.swift) 通过文件大小等检查识别可能的残缺缓存，并在某些错误时清理重下。这些检查是启发式，不是哈希完整性校验。Voice Buddy 应保护共享缓存：不得未经确认删除可能被其他应用使用的模型；优先校验固定版本清单与可信哈希，并给用户清晰恢复选项。

## 决策与验证

1. **不直接 fork 或替换方案**：以 Qwen3-ASR 0.6B（1.7B 为进阶候选）与小型文本模型的 Swift/MLX 应用内加载为首期方向，用已有 sidecar 做对照；两者只在同一真实样本、设备与权重下比较。记录冷/热加载、5 秒听写停止到结果、峰值内存、断网、崩溃和权限恢复。
2. **先验证音频与输入**：同一批中文、英文、法语、混说、静音、弱音、短停顿样本对比 VAD 前后漏字和幻觉；在备忘录、网页、Electron、终端、安全字段验证焦点变化、剪贴板竞争和 Undo。
3. **隔离模型管理**：分别测试已有服务、端口占用、服务身份、共享模型、残缺下载、版本迁移、卸载以及 8GB 内存压力。仅停止本应用管理的进程，不自动清理用户共享模型或卸载其他应用使用的 Ollama 模型。
4. **不以 README 代替证据**：固定 MacWispr、`speech-swift` 与模型版本；在引用或移植具体代码前复核 MIT 及依赖/权重许可与版权声明。任何速度或语言覆盖结论都必须由我们自己的测试支持。
