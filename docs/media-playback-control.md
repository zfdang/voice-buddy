# Voice Buddy 媒体播放暂停与恢复架构设计 (Media Playback Pause & Resume Architecture)

> **版本**：1.1.0  
> **生效日期**：2026-11-07  
> **适用范围**：Voice Buddy 媒体播放控制模块研发、维护与测试。

---

## 1. 背景与核心挑战

Voice Buddy 提供「录音时暂停背景媒体」（Pause Media During Dictation）功能。当用户长按快捷键说话或点击录音时，系统自动暂停背景音乐/视频；听写结束或取消后，自动恢复播放。

该功能的核心价值在于：
1. **防止杂音污染识别**：避免麦克风录入正在播放的视频对白、背景音乐，大幅提升 Silero VAD（语音活动检测）切片精度与端侧语音模型识别率。
2. **免除用户心智负担**：用户在看视频或听播客时临时需要语音输入，无需手动找播放器按空格暂停再切回来。

### 核心安全准则 (Core Invariant)
> **“未知或陈旧的播放状态绝不触发播放” (Unknown or stale playback state never starts playback)**
>
> 语音输入软件最严重的用户体验事故，就是在用户试图安静讲话或结束输入时，原本处于暂停状态的播放器突然开始大声外放音频。所有控制行为必须具备明确的进程定位、确切的状态检查、状态变更确认与闭环恢复，绝不允许盲目投机操作。

### macOS 平台的技术困境
macOS 并没有向第三方应用开放统一、简单、确定性的“全局媒体暂停与恢复”公共 API，市面各类播放器在技术实现上高度割裂：
* **原生应用**（Apple Music、Podcasts、Safari HTML5、QuickTime）：大多接入了系统的 NowPlaying 控制中心；
* **第三方独立播放器**（Movist Pro、IINA、VLC）：普遍没有接入 NowPlaying，通常采用自定义渲染管线（Metal/OpenGL），全屏播放时控制栏自动隐藏甚至无法被窗口无障碍树（AXWindow）稳定索引；
* **盲目使用系统媒体键（Media Key, `NX_KEYTYPE_PLAY`）的致命缺陷**：系统媒体键是无目标的全局 Toggle 翻转键。如果发送给原本已经暂停的播放器，反而会将其意外唤醒播放。

为此，Voice Buddy 建立了**双层确定性验证控制管线（Two-Tier Verified Control Pipeline）**，并坚决排除未经状态和目标验证的全局媒体键盲按。

---

## 2. 双层验证控制架构全景 (Two-Tier Verified Control Pipeline)

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

    T1_Query -- 否 / 超时 --> T2[第二层: 菜单栏 Accessibility 确定性控制]

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
        T2_Window -- 找到播放按钮 / 无按钮 --> EndIdle
    end

    T2_AudioProc -- 否 --> EndIdle

    subgraph ResumePhase["听写结束恢复流程: resumeIfPaused"]
        FinishDictation([听写结束 / 取消]) --> CheckPhase{检查当前状态 Phase}
        CheckPhase -- paused(pid) --> CheckStillPaused{确认该 PID 播放器<br>当前仍处于暂停状态?}
        CheckStillPaused -- 是 --> ExecResume[调用对应后端发送确定性 Play / 恢复指令]
        CheckStillPaused -- 否 (已被用户手动调整) --> SkipResume[跳过恢复: resumeSkipped]
        CheckPhase -- idle / 未曾暂停 --> DoNothing([不执行任何恢复操作])
        ExecResume --> ResetState([状态重置为 idle])
        SkipResume --> ResetState
        DoNothing --> ResetState
    end

    SetPausedState -.-> FinishDictation
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

### 第二层：桌面播放器控制 Accessibility & 目标锁定流验证
* **核心类**：`AccessibleMediaPlaybackBackend`（位于 `VoiceBuddyApp`）
* **核心突破点**：
  * 诸如 **Movist Pro、IINA、QuickTime Player、VLC** 这类本地播放器，全屏播放时往往把窗口控制栏自动隐藏，或者界面使用 Metal/OpenGL 统一纹理自绘，无障碍树（`kAXWindowsAttribute`）很难直接索引。
  * 根据 macOS 人机界面规范，所有规范的 macOS 应用都拥有系统主菜单栏（`kAXMenuBarAttribute`）。当应用处于前台时，**菜单栏永远存在，且其菜单项文字与播放器内核状态严格保持同步**（正在播放为 `Pause`/`暂停`，已暂停为 `Play`/`播放`）。
  * **后台窗口挑战与目标锁定流验证**：
    * 当 Movist Pro 处于**后台运行**时，macOS Accessibility 会将其菜单项标记为禁用状态（`enabled == false`），且后台窗口不接收无障碍点击；
    * 此时，Voice Buddy 通过 `AudioOutputProcesses.uniqueApplicationPID()` **唯一锁定正在外放音频的应用进程 PID**；
    * 采用目标锁定的媒体控制，并在 `verifyPause` 阶段**严格轮询该目标 PID 的 CoreAudio 音频输出流**（`AudioOutputProcesses.isAudioRunning(for: pid)`）：
      1. 发送暂停指令后，若且仅若该目标 PID 的外放音频真正由 `true` 转变为 `false`，才确认暂停成功（`pauseConfirmed`）；
      2. 若该应用不响应媒体键（如视频会议软件、游戏音效），外放音频保持为 `true`，`verifyPause` 判定失败（`pauseUnverified`），立即重置回 `idle`，**绝不记录暂停，听写结束时绝不触发任何恢复操作**；
      3. 听写结束恢复时，必须确认该目标 PID 依然存活且当前依然处于未发声状态，才执行恢复，**彻底解决未经验证与目标缺失的风险**。

---

## 4. 彻底解决未经验证的全局媒体键盲按 (Addressing P1 Review Risks)

在方案演进中审查提出的两项 P1 风险，通过本设计获得了彻底解决：

### P1 风险 1：活跃音频流不能证明播放器正在播放
* **机制约束**：系统不单凭 CoreAudio 有声音就认定是播放器，而是必须通过 `AudioOutputProcesses.uniqueApplicationPID()` 精准识别出**单一、合法的普通应用进程**；
* **双重验证闭环**：发出控制指令后，必须由状态机执行多轮验证（`verifyPause`），只有该应用的外放音频流**切实停止**，才进入 `paused(pid)` 状态。若未停止，立即废弃操作，绝不波及其他应用。

### P1 风险 2：恢复时无法确认首次按键的结果与目标
* **目标绑定**：首次操作必须将 `trackedPID` 牢牢绑定到特定进程；
* **恢复前置检查**：只有在首次成功确认暂停（`didPauseMedia == true`）且该 PID 依然存在且仍处于暂停状态的前提下，才执行恢复；如果首次验证失败，听写结束时保持静默，**彻底杜绝将原本暂停的 Apple Music / Spotify 意外唤醒**。

---

## 5. 状态机流转与防重入机制

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
             │ snapshot 为空 / 未播放           ▼    │ resumeIfPaused()
             │ 或 pause() 失败          ┌────────────────┐ 或未识别
             └─────────────────────────►│ verifyingPause │
                                        └───────┬────────┘
                                                │ pauseConfirmed
                                                ▼
                                        ┌────────────────┐
                                        │  paused(pid)   │
                                        └───────┬────────┘
                                                │ resumeIfPaused()
                                                ▼
                                        ┌────────────────┐
                                        │ checkingResume │
                                        └───────┬────────┘
                                                │
                                                ▼
                                        ┌────────────────┐
                                        │      idle      │
                                        └────────────────┘
```

### 极速按键/会话重叠保护（Carry Forward）
用户在快速按键、连击 Fn 或快捷键时，前一次的暂停/恢复异步查询可能尚未完成，新一次录音已经触发：
* 若前一次处于 `.verifyingPause` 或 `.paused(pid)`，新录音直接继承已有所有权，不重复向应用轰炸暂停指令；
* 若听写在异步探测返回前就提前结束（`ended == true`），一旦 `snapshot` 回调到达，立即检测 `self.ended`，不执行后续的暂停操作，防止听写结束后应用被反向暂停。

---

## 6. 诊断日志对照表 (Diagnostics Reference)

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

---

## 7. 自动化测试保障

相关单测位于 `Tests/` 目录，CI 与本地可通过 `swift test` 验证：
* [`Tests/VoiceBuddyCoreTests/MediaPlaybackControllerTests.swift`](file:///Users/zfdang/workspaces/voice-buddy-private/Tests/VoiceBuddyCoreTests/MediaPlaybackControllerTests.swift)：
  * 验证第一层（MediaRemote）与第二层（Fallback）的优先次序与生命周期；
  * 验证开局未暂停时，结束时绝不发送恢复按键；
  * 验证原本已知处于暂停状态的应用绝不被意外唤醒；
  * 验证验证暂停失败时不进入已暂停状态。
* [`Tests/VoiceBuddyAppTests/AccessibleMediaPlaybackTests.swift`](file:///Users/zfdang/workspaces/voice-buddy-private/Tests/VoiceBuddyAppTests/AccessibleMediaPlaybackTests.swift)：
  * 验证播放菜单名（`Playback`、`Controls`、`播放`、`控制`）识别规范；
  * 验证各语言菜单项（“暂停”、“Pause”、“播放”、“Play”）状态解析；
  * 验证虚拟麦克风（`BuddyMic2ch_UID`）排除逻辑，确保不干扰音频检测。
