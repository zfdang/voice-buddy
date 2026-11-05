import SwiftUI
import AppKit
import Carbon
import AVFoundation
import VoiceBuddyCore
import LaunchAtLogin
import KeyboardShortcuts

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmSpeechDelete = false
    @State private var confirmTextDelete = false
    private func t(_ en: String, _ zh: String) -> String { state.label(en, zh) }

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedTab) {
                Label(t("General", "通用"), systemImage: "slider.horizontal.3").tag(AppTab.general)
                Label(t("Permissions", "权限检查"), systemImage: "checkmark.shield").tag(AppTab.permissions)
                Label(t("Speech recognition", "语音识别"), systemImage: "waveform").tag(AppTab.speech)
                Label(t("Text model", "文本模型"), systemImage: "text.bubble").tag(AppTab.editor)
                Label(t("Result", "结果"), systemImage: "doc.text").tag(AppTab.recovery)
                Label(t("About", "关于"), systemImage: "info.circle").tag(AppTab.about)
            }.navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(nsImage: mascot).resizable().scaledToFit().frame(width: 50, height: 50)
                        VStack(alignment: .leading) {
                            Text("Voice Buddy").font(.title.bold())
                            Text(t("Your voice, on your Mac.", "你的声音，在本机变成文字。")).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if state.modelPreparing {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.status).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                ProgressView(value: state.modelProgress).frame(maxWidth: 300)
                                Button(t("Cancel", "取消")) { state.cancel() }
                            }
                        }
                    } else if state.recording {
                        HStack {
                            Image(systemName: "mic.fill").foregroundStyle(.red)
                            Text(t("Listening", "正在听你说"))
                            ProgressView(value: min(Double(state.level) * 12, 1)).frame(width: 100)
                            Button(t("Cancel", "取消")) { state.cancel() }
                        }
                    } else if state.busy {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(state.status).font(.caption).foregroundStyle(.secondary)
                            Button(t("Cancel", "取消")) { state.cancel() }
                        }
                    }
                    Divider()
                    switch state.selectedTab {
                    case .general: general
                    case .permissions: permissions
                    case .speech: speech
                    case .editor: editor
                    case .recovery: recovery
                    case .about: about
                    }
                    Spacer()
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
        .onChange(of: state.status) { _, _ in
            if !state.result.isEmpty && !state.recording && !state.busy {
                state.selectedTab = .recovery
            }
        }
    }

    private var mascot: NSImage {
        if let url = Bundle.module.url(forResource: "mascot", withExtension: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage()
    }

    private func settingRow<Control: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: subtitle == nil ? .center : .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 3)
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 8) {
                content()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Shortcut & Dictation Mode
            settingsCard(title: t("Shortcut & Recording", "快捷键与录音方式")) {
                settingRow(
                    title: t("Dictation Shortcut", "全局快捷键"),
                    subtitle: t("Press anywhere to trigger dictation", "在 macOS 任意应用中直接唤醒语音输入")
                ) {
                    KeyboardShortcuts.Recorder(for: .toggleDictation)
                }
                Divider()
                settingRow(
                    title: t("Recording Mode", "录音触发模式"),
                    subtitle: t("Hold to talk or press once to toggle recording", "选择长按说话还是单次敲击启停")
                ) {
                    Picker("", selection: Binding(get: { state.preferences.holdToTalk ?? true }, set: { state.preferences.holdToTalk = $0 })) {
                        Text(t("Hold to talk", "按住说话")).tag(true)
                        Text(t("Press to start / stop", "按键切换录音")).tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(state.recording || state.busy)
                }
            }

            // 2. Audio & Feedback
            settingsCard(title: t("Audio & Feedback", "音频输入与提示")) {
                settingRow(
                    title: t("Microphone", "麦克风输入源"),
                    subtitle: t("Select audio capture device", "指定用于语音听写的输入麦克风")
                ) {
                    Picker("", selection: $state.preferences.microphoneUID) {
                        Text(t("System default", "系统默认")).tag("")
                        ForEach(AudioDevices.devices(), id: \.0) { device in Text(device.1).tag(device.0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                settingRow(
                    title: t("Pause Media During Dictation", "录音时暂停背景音乐"),
                    subtitle: t("Pause background music while speaking and resume when done", "开始说话时自动暂停背景音乐或播客，录音结束后自动恢复")
                ) {
                    Toggle("", isOn: $state.preferences.pauseMediaDuringRecording)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider()
                settingRow(
                    title: t("Sound Feedback", "操作提示音"),
                    subtitle: t("Play subtle sounds when dictation begins and finishes", "在录音开始与结束时播放提示音效")
                ) {
                    Toggle("", isOn: $state.preferences.sounds)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            // 3. Text Processing & Insertion
            settingsCard(title: t("Text & Insertion", "文本润色与输入")) {
                settingRow(
                    title: t("Text Refinement", "文字整理力度"),
                    subtitle: t("Degree of punctuation and stylistic cleanup", "调整文本标点修整与口语语气整理程度")
                ) {
                    Picker("", selection: $state.preferences.refinement) {
                        Text(t("Original", "原文")).tag(Refinement.original)
                        Text(t("Light", "轻微整理")).tag(Refinement.light)
                        Text(t("Moderate", "适度整理")).tag(Refinement.moderate)
                        Text(t("Rewrite", "完全重写")).tag(Refinement.rewrite)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                settingRow(
                    title: t("Auto-Insert Text", "确认安全时自动插入"),
                    subtitle: t("Automatically inject transcription at active cursor position", "在安全文本框中直接将文字插入到当前输入焦点光标处")
                ) {
                    Toggle("", isOn: $state.preferences.autoInsert)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            // 4. System & Startup
            settingsCard(title: t("System & Launch", "系统与启动")) {
                settingRow(
                    title: t("Interface Language", "界面显示语言"),
                    subtitle: t("Select display language for Voice Buddy", "设置 Voice Buddy 界面与菜单显示语言")
                ) {
                    Picker("", selection: $state.preferences.interfaceLanguage) {
                        Text(t("System", "跟随系统")).tag("system")
                        Text("English").tag("en")
                        Text("简体中文").tag("zh")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                settingRow(
                    title: t("Launch at Login", "开机自动启动"),
                    subtitle: t("Start Voice Buddy in the menu bar when Mac starts", "开机登录系统时自动在后台菜单栏启动")
                ) {
                    LaunchAtLogin.Toggle {
                        Text("")
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
        .frame(maxWidth: 580)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Voice Buddy works completely offline. Permissions are only used for local audio capture and text insertion.", "Voice Buddy 完全在本地离线运行。系统权限仅用于本机录音与向当前光标位置输入文字。")).foregroundStyle(.secondary)

            // Overall status card
            HStack(spacing: 12) {
                Image(systemName: (state.micAuthorized && state.axAuthorized) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle((state.micAuthorized && state.axAuthorized) ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text((state.micAuthorized && state.axAuthorized) ? t("All required permissions granted", "所有必要权限均已就绪") : t("Permissions needed", "需要授予必要权限"))
                        .font(.headline)
                    Text((state.micAuthorized && state.axAuthorized) ? t("Voice Buddy is fully ready for offline dictation and insertion.", "语音输入与自动插入功能已全部就绪。") : t("Please grant the missing permissions below to enable seamless voice input.", "请根据下方指引完成授权，以体验完整的跨应用语音输入。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("Re-check", "重新检查")) {
                    state.refreshPermissions()
                }.accessibilityLabel(t("Re-check", "重新检查"))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            // Microphone permission card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(t("Microphone Access", "麦克风权限"), systemImage: "mic.fill")
                        .font(.headline)
                    Spacer()
                    if state.micAuthorized {
                        Label(t("Authorized", "已授权"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else if state.micStatus == .denied {
                        Label(t("Denied", "已拒绝"), systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    } else {
                        Label(t("Not Determined", "待授权"), systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
                Text(t("Allows Voice Buddy to capture your voice from the microphone for local speech recognition. Audio is never recorded to disk or sent online.", "允许 Voice Buddy 采集您的语音并由本地模型识别。录音仅在内存中处理，绝不上传云端，不保存音频文件。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if !state.micAuthorized {
                        if state.micStatus == .notDetermined {
                            Button(t("Request Microphone Permission", "请求麦克风权限")) {
                                state.requestMicrophoneAccess()
                            }.accessibilityLabel(t("Request Microphone Permission", "请求麦克风权限"))
                        }
                        Button(t("Open System Settings", "打开系统麦克风设置")) {
                            state.openSystemSettings(for: "microphone")
                        }.accessibilityLabel(t("Open System Settings", "打开系统麦克风设置"))
                    } else {
                        Button(t("Open System Settings", "打开系统麦克风设置")) {
                            state.openSystemSettings(for: "microphone")
                        }.accessibilityLabel(t("Open System Settings", "打开系统麦克风设置"))
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            // Accessibility permission card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(t("Accessibility Access", "辅助功能权限"), systemImage: "command")
                        .font(.headline)
                    Spacer()
                    if state.axAuthorized {
                        Label(t("Authorized", "已授权"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else {
                        Label(t("Not Authorized", "未授权"), systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
                Text(t("Allows Voice Buddy to detect the active text box in other applications and safely insert the recognized text at your cursor without losing undo history.", "允许 Voice Buddy 获取当前正在输入的应用焦点，并将文字自动粘贴回光标位置。未授权时仍可识别，但需手动复制。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if !state.axAuthorized {
                        Button(t("Request Accessibility Permission", "请求辅助功能权限")) {
                            state.requestAccessibilityAccess()
                        }.accessibilityLabel(t("Request Accessibility Permission", "请求辅助功能权限"))
                    }
                    Button(t("Open System Settings", "打开系统辅助功能设置")) {
                        state.openSystemSettings(for: "accessibility")
                    }.accessibilityLabel(t("Open System Settings", "打开系统辅助功能设置"))
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            // Privacy notes
            VStack(alignment: .leading, spacing: 8) {
                Text(t("Privacy & Security Commitments", "隐私与安全承诺")).font(.subheadline.bold())
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                    Text(t("100% Offline: Models run directly on Apple Silicon via Metal / Core ML with zero network dependencies during dictation.", "100% 本地离线：听写和文本整理直接在芯片上运行，听写过程断网可用。")).font(.caption)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                    Text(t("Clipboard Hygiene: Transient pasteboard markers prevent third-party history managers (Raycast, Paste, Maccy) from indexing your dictations.", "剪贴板瞬态保护：写入时携带 Transient 标记，防止 Raycast、Paste、Maccy 等第三方工具抓取。")).font(.caption)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                    Text(t("Secure Field Guard: Automatically disables auto-insertion if a secure password field is active.", "密码框安全阻断：检测到密码或安全输入控件时自动中止插入，避免密码泄露。")).font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
        }
        .frame(maxWidth: 620)
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Model Selection Card
            settingsCard(title: t("Speech Recognition Model", "语音识别模型")) {
                settingRow(
                    title: t("Recognition Model", "识别模型规格"),
                    subtitle: t("On-device speech-to-text acoustic model", "端侧声学转录模型")
                ) {
                    Picker("", selection: $state.preferences.speechModel) {
                        Text("Qwen3-ASR 0.6B (推荐 · 480 MB)").tag("mlx-community/Qwen3-ASR-0.6B-8bit")
                        Text("Qwen3-ASR 1.7B (高精 · 16 GB+ Mac)").tag("mlx-community/Qwen3-ASR-1.7B-8bit")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(state.busy || state.recording)
                    .onChange(of: state.preferences.speechModel) { _, _ in
                        state.ready = false
                        state.checkModelCacheStatus()
                    }
                }
                Divider()
                settingRow(
                    title: t("Spoken Language", "识别语言"),
                    subtitle: t("Select primary spoken language or auto-detect", "选择听写主要使用的语言或开启多语种自动混说检测")
                ) {
                    Picker("", selection: $state.preferences.speechLanguage) {
                        Text(t("Automatic", "自动识别 / 混说")).tag("auto")
                        Text("中文").tag("Chinese")
                        Text("English").tag("English")
                        Text("Français").tag("French")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // 2. Status & Storage Card
            settingsCard(title: t("Model Status & Storage", "下载与运行状态")) {
                HStack(alignment: .top, spacing: 12) {
                    if state.speechPreparing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Downloading / Loading speech model…", "正在准备语音识别模型…"))
                                .font(.headline)
                            Text(state.speechProgressMessage.isEmpty ? t("Downloading weights from Hugging Face…", "正在下载模型权重…") : state.speechProgressMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if state.ready {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Ready in Memory", "已载入内存 · 随时可用"))
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text(t("Acoustic and VAD models are ready for instant dictation.", "声学识别与语音检测模型已就绪，按下快捷键即可开始听写。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if state.isSpeechDownloaded {
                        Image(systemName: "externaldrive.fill.badge.checkmark")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Downloaded (Not in Memory)", "已下载至本地 · 未载入内存"))
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Text(t("Model files are saved locally. Click Load or it loads on first shortcut press.", "模型已下载至本机，点击载入或在首次按快捷键时自动加载。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Not Downloaded", "尚未下载"))
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(t("Model downloads once from Hugging Face and runs 100% locally thereafter.", "首次使用前从 Hugging Face 下载，之后全流程在 Mac 本机离线运行。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if state.speechPreparing {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(t("Preparation Progress", "准备进度"))
                                .font(.caption.bold())
                            Spacer()
                            Text("\(Int(state.speechProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: state.speechProgress)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    if state.speechPreparing {
                        Button(t("Cancel", "取消")) { state.cancel() }
                    } else if state.ready {
                        Button(t("Reload into Memory", "重新加载")) { state.prepareSpeech() }
                            .disabled(state.busy)
                        Button(role: .destructive) {
                            confirmSpeechDelete = true
                        } label: {
                            Text(t("Delete Local Cache…", "删除本地缓存…"))
                        }
                        .disabled(state.busy || state.recording)
                    } else if state.isSpeechDownloaded {
                        Button(t("Load into Memory", "载入内存")) { state.prepareSpeech() }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.busy)
                        Button(role: .destructive) {
                            confirmSpeechDelete = true
                        } label: {
                            Text(t("Delete Local Cache…", "删除本地缓存…"))
                        }
                        .disabled(state.busy || state.recording)
                    } else {
                        Button(t("Download Model", "下载语音模型")) { state.prepareSpeech() }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.busy)
                    }
                }
                .confirmationDialog(t("Delete this speech model?", "删除当前语音模型？"), isPresented: $confirmSpeechDelete) {
                    Button(t("Delete", "删除"), role: .destructive) { state.removeSpeechModel() }
                }
            }
        }
        .frame(maxWidth: 580)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Model Selection Card
            settingsCard(title: t("Text Refinement Model", "文本润色模型选择")) {
                settingRow(
                    title: t("Select Model", "选择模型规格"),
                    subtitle: t("Local LLM used for Moderate editing and Rewrite modes", "用于“适度整理”与“完全重写”模式的端侧大语言模型")
                ) {
                    Picker("", selection: $state.preferences.textModel) {
                        Text("Qwen 3.5 0.8B (INT5 · 494 MB · 极速轻量)").tag("qwen35-text-0.8b-int5")
                        Text("Qwen 3.5 0.8B (INT8 · 763 MB · 高精润色)").tag("qwen35-text-0.8b-int8")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(state.busy || state.recording)
                    .onChange(of: state.preferences.textModel) { _, _ in
                        state.editorReady = false
                        state.checkModelCacheStatus()
                    }
                }
            }

            // 2. Status & Storage Card
            settingsCard(title: t("Model Status & Storage", "下载与运行状态")) {
                HStack(alignment: .top, spacing: 12) {
                    if state.editorPreparing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Downloading / Loading model…", "正在下载 / 加载模型…"))
                                .font(.headline)
                            Text(state.editorProgressMessage.isEmpty ? t("Fetching weights from Hugging Face…", "正在从 Hugging Face 获取权重…") : state.editorProgressMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if state.editorReady {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Ready in Memory", "已载入内存 · 随时可用"))
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text(t("Model is resident in unified memory for instant zero-latency refinement.", "模型已常驻统一内存，可进行毫秒级零延迟文字润色。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if state.isEditorDownloaded {
                        Image(systemName: "externaldrive.fill.badge.checkmark")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Downloaded (Not in Memory)", "已下载至本地 · 未载入内存"))
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Text(t("Model files exist on disk. Preload it now or it will load automatically on first dictation.", "模型文件已保存在本机。可立即载入，或在首次听写润色时自动加载。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Not Downloaded", "尚未下载"))
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(t("Model needs to be downloaded once (~500 MB) before moderate or rewrite editing can run.", "首次使用适度整理或完全重写前需下载一次模型文件（约 500 MB）。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if state.editorPreparing {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(t("Download / Load Progress", "下载与加载进度"))
                                .font(.caption.bold())
                            Spacer()
                            Text("\(Int(state.editorProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: state.editorProgress)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    if state.editorPreparing {
                        Button(t("Cancel", "取消下载")) {
                            state.cancel()
                        }
                    } else if state.editorReady {
                        Button(t("Reload into Memory", "重新加载")) {
                            state.prepareEditor()
                        }
                        .disabled(state.busy)

                        Button(role: .destructive) {
                            confirmTextDelete = true
                        } label: {
                            Text(t("Delete Local Cache…", "删除本地缓存…"))
                        }
                        .disabled(state.busy || state.recording)
                    } else if state.isEditorDownloaded {
                        Button(t("Load into Memory", "载入内存")) {
                            state.prepareEditor()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.busy)

                        Button(role: .destructive) {
                            confirmTextDelete = true
                        } label: {
                            Text(t("Delete Local Cache…", "删除本地缓存…"))
                        }
                        .disabled(state.busy || state.recording)
                    } else {
                        Button(t("Download Model", "下载文本模型")) {
                            state.prepareEditor()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.busy)
                    }
                }
                .confirmationDialog(t("Delete this text model from disk?", "从本机删除此文本模型？"), isPresented: $confirmTextDelete) {
                    Button(t("Delete", "删除"), role: .destructive) { state.removeTextModel() }
                } message: {
                    Text(t("Model files will be removed from your disk. You can re-download anytime.", "模型文件将从本机存储中移除，后续需要时可随时重新下载。"))
                }
            }

            // 3. How Refinement Works Guide
            settingsCard(title: t("How Refinement Works", "润色模式与大模型的关系")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Original & Light modes", "原文与轻微整理模式")).font(.subheadline.bold())
                            Text(t("Run 100% locally with zero MLX LLM overhead. Light mode uses regex to instantly remove verbal pauses like 'uh', 'um', '那个'.", "完全基于本地毫秒级规则，不消耗大语言模型显存。轻微整理即刻智能剔除“嗯、啊、那个”等口癖。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Moderate & Rewrite modes", "适度整理与完全重写模式")).font(.subheadline.bold())
                            Text(t("Leverage this local Qwen 3.5 model on Apple Neural Engine to restructure sentences, fix grammar, and output polished prose.", "在 Apple 神经引擎上调用本模型进行语序重构、标点润色与书面化排版，全程同样 100% 本地离线。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 580)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Review before copying or inserting.", "请检查后复制或插入。 ")).foregroundStyle(.secondary)
            TextEditor(text: $state.result).frame(minHeight: 160).border(.quaternary)
            HStack(spacing: 12) {
                Button(t("Copy", "复制")) { state.copyResult() }.accessibilityLabel(t("Copy", "复制"))
                Button(t("Show original", "查看原文")) { state.result = state.original }.accessibilityLabel(t("Show original", "查看原文"))
                Button(t("Insert", "插入")) {
                    if !state.insertIfSafe(state.result) {
                        state.status = t("Return to the original field and copy manually.", "请回到原输入框并手动粘贴。")
                    }
                }.accessibilityLabel(t("Insert", "插入"))
                if !state.status.isEmpty {
                    Text(state.status).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Version Info Card
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Version Information", "版本信息")).font(.headline)
                VStack(spacing: 8) {
                    HStack {
                        Text(t("Current version", "当前版本")).foregroundStyle(.secondary)
                        Spacer()
                        Text("v\(appVersion) (\(t("Build", "构建号")) \(appBuild))")
                            .font(.system(.body, design: .monospaced))
                    }
                    Divider()
                    HStack {
                        Text(t("Architecture", "芯片架构")).foregroundStyle(.secondary)
                        Spacer()
                        #if arch(arm64)
                        Text("Apple Silicon (arm64)")
                        #else
                        Text("Intel (x86_64)")
                        #endif
                    }
                    Divider()
                    HStack {
                        Text(t("Update engine", "更新机制")).foregroundStyle(.secondary)
                        Spacer()
                        Text("Sparkle Framework")
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 2. Software Updates Card
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Software Update", "软件更新")).font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Keep Voice Buddy up to date", "保持最新版本体验"))
                            .font(.subheadline.bold())
                        Text(t("Check for new versions, enhancements, and fixes.", "检查新版本发布、性能改进以及问题修复。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("Check for Updates…", "检查更新…")) {
                        state.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 3. Project Intro & Links Card
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Introduction & Links", "项目介绍与链接")).font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    Text(t(
                        "Voice Buddy runs entirely offline on your Mac. Using local speech recognition and lightweight language models, it turns spoken words into clean, punctuated text in milliseconds without sending any audio or text data to the cloud. Dictation is activated exclusively via your global keyboard shortcut.",
                        "Voice Buddy 完全在你的 Mac 本地离线运行。通过本机部署的语音识别与轻量语言模型，在毫秒级内将你的语音转化为精准、带有合理标点的文字，全程绝不向云端发送任何音频或文本数据，充分保障你的隐私安全。听写功能完全由你的全局快捷键唤醒。"
                    ))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(spacing: 8) {
                        HStack {
                            Label("GitHub Repository", systemImage: "link")
                            Spacer()
                            Link("github.com/zfdang/voice-buddy", destination: URL(string: "https://github.com/zfdang/voice-buddy")!)
                        }
                        Divider()
                        HStack {
                            Label(t("Releases & Downloads", "版本发布与下载"), systemImage: "shippingbox")
                            Spacer()
                            Link(t("View Releases", "查看发布页"), destination: URL(string: "https://github.com/zfdang/voice-buddy/releases")!)
                        }
                        Divider()
                        HStack {
                            Label(t("Issues & Feedback", "问题反馈与建议"), systemImage: "bubble.left.and.exclamationmark.bubble.right")
                            Spacer()
                            Link(t("Submit Issue", "提交反馈"), destination: URL(string: "https://github.com/zfdang/voice-buddy/issues")!)
                        }
                    }

                    Divider()

                    Text(t("Built with Sparkle, KeyboardShortcuts, LaunchAtLogin, MediaRemoteAdapter, Whisper.cpp, and MLX.", "基于 Sparkle、KeyboardShortcuts、LaunchAtLogin、MediaRemoteAdapter、Whisper.cpp 与 MLX 开源生态构建。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: 560)
    }
}
