# Voice Buddy 媒体播放暂停与恢复架构设计 (Media Playback Pause & Resume Architecture)

> **版本**：1.0.0  
> **生效日期**：2026-11-07  
> **适用范围**：Voice Buddy 媒体播放控制模块研发、维护与测试。

---

## 1. 背景与核心挑战

Voice Buddy 提供「录音时暂停背景媒体」（Pause Media During Dictation）功能。当用户长按快捷键说话或点击录音时，系统自动暂停背景音乐/视频；听写结束或取消后，自动恢复播放。

该功能的核心价值在于：
1. **防止杂音污染识别**：避免麦克风录入正在播放的视频对白、背景音乐，大幅提升 Silero VAD（语音活动检测）切片精度与端侧语音模型识别率。
2. **免除用户心智负担**：用户在看视频或听播客时临时需要语音输入，无需手动找播放器按空格暂停再切回来。

### macOS 平台的技术困境
macOS 并没有向第三方应用开放统一、简单、确定性的“全局媒体暂停与恢复”公共 API，市面各类播放器在技术实现上高度割裂：
* **原生应用**（Apple Music、Podcasts、Safari HTML5、QuickTime）：大多接入了系统的 NowPlaying 控制中心；
* **第三方独立播放器**（Movist Pro、IINA、VLC）：普遍没有接入 NowPlaying，通常采用自定义渲染管线（Metal/OpenGL），全屏播放时控制栏自动隐藏甚至无法被窗口无障碍树（AXWindow）稳定索引；
* **网页与跨平台应用**（Chrome 后台标签、Electron 客户端、游戏）：既没有原生菜单也没有 NowPlaying；
* **系统媒体键（Media Key, `NX_KEYTYPE_PLAY`）的双刃剑特性**：媒体键在系统层面是一个 **Toggle（翻转键）**。如果盲目发送媒体键，对于**原本已经暂停的视频**，反而会被意外触发播放。

为此，Voice Buddy 设计了**三层递进的媒体控制管线（Three-Tier Control Pipeline）**。

---

## 2. 三层控制架构全景 (Three-Tier Control Pipeline)

```mermaid
flowchart TD
    Start([用户触发录音: pauseIfPlaying]) --> CheckActive{是否启用该选项<br>且不在录音中?}
    CheckActive -- 否 --> EndIdle([结束: 不做处理])
    CheckActive -- 是 --> T1[第一层: 系统 MediaRemote 探测]

    subgraph Tier1["第一层: MediaRemote (原生最高优先级)"]
        T1 --> T1_Query{MRMediaRemote 是否报告<br>正在播放的应用?}
        T1_Query -- 是 (isPlaying == true) --> T1_Pause[发送确定性暂停指令: kMRPause]
        T1_Pause --> T1_Verify[多轮验证确认暂停状态]
        T1_Verify --> SetPausedState[标记: paused(pid), didPauseMedia = true]
    end

    T1_Query -- 否 / 超时 --> T2[第二层: 菜单栏 Accessibility 控制]

    subgraph Tier2["第二层: 菜单栏 AXMenuBar (专治桌面播放器)"]
        T2 --> T2_AudioProc{CoreAudio 能否识别<br>外放音频的应用 PID?}
        T2_AudioProc -- 是 --> T2_Menu{检查该应用 AXMenuBar<br>Playback / 播放 菜单项}
        T2_Menu -- 菜单项为「暂停 / Pause」 --> T2_ClickPause[点击菜单项暂停]
        T2_ClickPause --> T2_Verify[确认菜单项切换为「播放」]
        T2_Verify --> SetPausedState
        T2_Menu -- 菜单项为「播放 / Play」 --> T2_AlreadyPaused[判定为原本已暂停: 保持静止]
        T2_AlreadyPaused --> EndIdle
        T2_Menu -- 菜单不可读 --> T2_Window[降级检查窗口中的控制按钮]
        T2_Window -- 找到确切暂停按钮 --> T2_ClickPause
    end

    T2_AudioProc -- 否 --> T3[第三层: CoreAudio 活跃外放检测 + 媒体键兜底]
    T2_Window -- 未找到有效控件 --> T3

    subgraph Tier3["第三层: 媒体键 Toggle 兜底 (广谱兼容)"]
        T3 --> T3_CheckAudio{CoreAudio 检测扬声器/耳机<br>是否有非本应用的活跃音频流?}
        T3_CheckAudio -- 是 (确实有声音在播放) --> T3_SendKey[模拟发送全局 NX_KEYTYPE_PLAY]
        T3_SendKey --> SetToggleState[进入状态: toggleSent, didPauseMedia = true]
        T3_CheckAudio -- 否 (当前无声音外放) --> EndIdle
    end

    subgraph ResumePhase["听写结束恢复流程: resumeIfPaused"]
        FinishDictation([听写结束 / 取消]) --> CheckPhase{检查当前状态 Phase}
        CheckPhase -- paused(pid) --> ExecResume[调用对应后端发送确定性 Play / 恢复指令]
        CheckPhase -- toggleSent --> ExecToggleRestore[再次发送 NX_KEYTYPE_PLAY 翻转恢复]
        CheckPhase -- idle / 未曾暂停 --> DoNothing([不执行任何恢复操作])
        ExecResume --> ResetState([状态重置为 idle])
        ExecToggleRestore --> ResetState
        DoNothing --> ResetState
    end

    SetPausedState -.-> FinishDictation
    SetToggleState -.-> FinishDictation
```

---

## 3. 分层实现细节

### 第一层：系统级 MediaRemote（原生高精度控制）
* **核心类**：`SystemMediaPlaybackBackend`（位于 `VoiceBuddyCore`）
* **技术实现**：
  * 动态加载私有库 `/System/Library/PrivateFrameworks/MediaRemote.framework`；
  * 调用 `MRMediaRemoteGetNowPlayingApplicationPID` 与 `MRMediaRemoteGetNowPlayingApplicationIsPlaying` 获取系统当前播放器状态；
  * 发送明确的指令：`MRMediaRemoteSendCommand(1, nil)`（暂停 `kMRPause`）与 `MRMediaRemoteSendCommand(0, nil)`（播放 `kMRPlay`）。
* **优势**：
  * 指令具有绝对性（Explicit），不是 Toggle。向已暂停的应用发 `kMRPause` 不会引发误播；
  * 状态明确，毫秒级响应。
* **适用对象**：Apple Music、Podcasts、Safari HTML5、Chrome（启用媒体会话）等原生应用。

---

### 第二层：菜单栏与无障碍控制 Accessibility（专治桌面播放器）
* **核心类**：`AccessibleMediaPlaybackBackend`（位于 `VoiceBuddyApp`）
* **核心突破点**：
  * 诸如 **Movist Pro、IINA、QuickTime Player、VLC** 这类本地播放器，全屏播放时往往把窗口控制栏自动隐藏，或者界面使用 Metal/OpenGL 统一纹理自绘，无障碍树（`kAXWindowsAttribute`）很难直接索引。
  * 但根据 macOS 人机界面规范，所有规范的 macOS 应用都拥有系统主菜单栏（`kAXMenuBarAttribute`）。无论是全屏模式还是窗口隐藏模式，**菜单栏永远存在，且其菜单项文字与播放器内核状态严格保持同步**：
    * 正在播放时：`Playback`（或中文系统下的 `播放`、`控制`）菜单下的子项必定显示为 **`Pause`（`暂停`）**；
    * 处于暂停时：该菜单项必定自动切换为 **`Play`（`播放`）**。
* **操作逻辑**：
  1. 通过 `AudioOutputProcesses.uniqueApplicationPID()` 定位正在输出音频的应用进程；
  2. 使用 `AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute, ...)` 索引其主菜单；
  3. 扫描 `isPlaybackMenu(title)`（匹配 `Playback`、`Controls`、`播放`、`控制` 等）；
  4. 检查其子菜单项：
     * 若匹配 `menuPlaybackState == true`（显示“暂停”）：执行 `AXUIElementPerformAction(item, kAXPressAction)` 点击暂停，并记录确切的控件指针与 `processID`；
     * 若匹配 `menuPlaybackState == false`（显示“播放”）：证明播放器当前本来就已经暂停，Voice Buddy 保持静默，不做任何多余动作；
  5. 听写结束时，若由我方暂停，再次对该菜单项（此时已变成“播放”）执行 `kAXPressAction` 即可恢复播放。

---

### 第三层：CoreAudio 活跃外放检测 + 媒体键兜底（广谱兼容）
* **核心类**：`MediaKeyFallback` 与 `AudioOutputProcesses`（位于 `VoiceBuddyApp`）
* **解决的问题**：
  针对没有接入 MediaRemote、也没有规范菜单栏的特殊客户端（如某些跨平台视频工具、游戏音效、未知网页音频），落实用户提出的“听写前有声就按一次暂停，听写后如果是我们暂停的就按一次恢复”闭环逻辑。
* **健壮的 CoreAudio 音频检测**：
  * 读取 CoreAudio HAL `kAudioHardwarePropertyProcessObjectList`；
  * 逐个查询 `kAudioProcessPropertyIsRunningOutput`（输出流是否处于活跃推流状态）；
  * **必须排除干扰项**：
    1. 排除 Voice Buddy 应用自身（`pid == getpid()`）；
    2. 排除写入虚拟麦克风（如 `Voice Input Buddy Mic`，UID 为 `BuddyMic2ch_UID`）的音频流，避免语音输入自身的回路被误当成背景播放器；
    3. 遇到非普通应用的系统级守护进程（如 `coreaudiod`）采用 `continue` 容错跳过，而不是中断返回空。
* **按键与状态机联动**：
  * 只有在 `hasActiveAudioOutput() == true`（确认扬声器/耳机当前确实有实际声音在播放）时，才模拟发送系统媒体键：
    ```swift
    // NX_KEYTYPE_PLAY (16) 在 system-defined 媒体事件中的封装
    let key = 16 << 16
    let down = NSEvent.otherEvent(with: .systemDefined, ..., data1: key | (0x0a << 8), ...)
    let up   = NSEvent.otherEvent(with: .systemDefined, ..., data1: key | (0x0b << 8), ...)
    down?.cgEvent?.post(tap: .cghidEventTap)
    up?.cgEvent?.post(tap: .cghidEventTap)
    ```
  * 发送后状态机迁移至 `.toggleSent`，并置 `didPauseMedia = true`；
  * 听写结束调用 `resumeIfPaused()` 时：
    * **若当前处于 `.toggleSent`**：再次发送一次 `NX_KEYTYPE_PLAY` 恢复播放，并记录 `media.mediaKeyRestoreSent`；
    * **若开始时未检测到声音（处于 `.idle`）**：绝对不发送任何按键，**彻底杜绝将原本暂停的视频误唤醒的问题**。

---

## 4. 状态机流转与防重入机制

在 `VoiceBuddyCore/MediaPlaybackController.swift` 中，所有决策严格在 `@MainActor` 线程串行执行，避免并发数据竞争：

```
       ┌───────────┐
       │   idle    │◄────────────────────────────────┐
       └─────┬─────┘                                 │
             │ pauseIfPlaying()                      │
             ▼                                       │
       ┌───────────┐  snapshot 有效 & pause()成功    │
       │ checking  ├────────────────────────────┐    │
       └─────┬─────┘                            │    │
             │                                  │    │
             │ snapshot 为空 & hasActiveOutput  ▼    │ resumeIfPaused()
             │ 且 toggle() 成功         ┌────────────────┐ 或未识别
             ▼                          │ verifyingPause │
       ┌───────────┐                    └───────┬────────┘
       │ toggleSent│                            │ pauseConfirmed
       └─────┬─────┘                            ▼
             │                          ┌────────────────┐
             │ resumeIfPaused()         │  paused(pid)   │
             │ 触发一次恢复按键          └───────┬────────┘
             │                                  │ resumeIfPaused()
             │                                  ▼
             │                          ┌────────────────┐
             │                          │ checkingResume │
             │                          └───────┬────────┘
             │                                  │
             └──────────────────────────────────┴────────────┘
```

### 极速按键/会话重叠保护（Carry Forward）
用户在快速按键、连击 Fn 或快捷键时，前一次的暂停/恢复异步查询可能尚未完成，新一次录音已经触发：
* 若前一次处于 `.verifyingPause` 或 `.paused(pid)`，新录音直接继承已有所有权，不重复向应用轰炸暂停指令；
* 若听写在异步探测返回前就提前结束（`ended == true`），一旦 `snapshot` 回调到达，立即检测 `self.ended`，不执行后续的暂停操作，防止听写结束后应用被反向暂停。

---

## 5. 诊断日志对照表 (Diagnostics Reference)

开发调试或用户反馈时，可通过 Finder 查看 `~/Library/Logs/VoiceBuddy/diagnostics.log` 中的媒体相关记录：

| 日志事件 (`event`) | 含义与排查指引 |
| :--- | :--- |
| `media.checkStarted` | 用户开始录音，启动媒体播放状态检测。 |
| `media.player_control available=true playing=true` | Accessibility（菜单栏或窗口按钮）成功检测到播放器且处于播放中。 |
| `media.pauseSent` | 已向播放器发送暂停请求（MediaRemote 或 Accessibility）。 |
| `media.pauseConfirmed` | 再次检查确认播放器已实际进入暂停状态。 |
| `media.resumeSent` | 录音结束，已向播放器发送恢复播放指令。 |
| `media.resumeSkipped` | 录音结束时，检测到播放器已被用户手动调整或其他原因，跳过恢复。 |
| `media.notPlayingOrUnavailable` | 系统没有播放中的媒体，或者原本就已经处于暂停状态，无需操作。 |
| `media.mediaKeySent` | 前两层未命中，第三层检测到活跃声音外放，已模拟发送媒体键暂停。 |
| `media.mediaKeyRestoreSent` | 录音结束，按序发送媒体键恢复播放。 |
| `media.mediaKeyFailed` | 媒体键模拟创建或发送失败（通常因辅助功能权限未授权）。 |

---

## 6. 自动化测试保障

相关单测位于 `Tests/` 目录，CI 与本地可通过 `swift test` 验证：
* [`Tests/VoiceBuddyCoreTests/MediaPlaybackControllerTests.swift`](file:///Users/zfdang/workspaces/voice-buddy-private/Tests/VoiceBuddyCoreTests/MediaPlaybackControllerTests.swift)：
  * 验证第一层（MediaRemote）与第二层（Fallback）的优先次序；
  * 验证第三层（`MediaToggleBackend`）仅在无确定性状态但有活跃声音时才发送媒体键；
  * 验证开局未暂停时，结束时绝不发送恢复按键；
  * 验证原本已知处于暂停状态的应用绝不被媒体键意外唤醒。
* [`Tests/VoiceBuddyAppTests/AccessibleMediaPlaybackTests.swift`](file:///Users/zfdang/workspaces/voice-buddy-private/Tests/VoiceBuddyAppTests/AccessibleMediaPlaybackTests.swift)：
  * 验证播放菜单名（`Playback`、`Controls`、`播放`、`控制`）识别规范；
  * 验证各语言菜单项（“暂停”、“Pause”、“播放”、“Play”）状态解析；
  * 验证虚拟麦克风（`BuddyMic2ch_UID`）排除逻辑，确保不干扰音频检测。
