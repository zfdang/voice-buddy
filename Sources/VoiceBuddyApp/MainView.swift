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
    @State private var speechModelToDelete: String? = nil
    @State private var confirmTextDelete = false
    @State private var textModelToDelete: String? = nil
    @State private var diagnosticsError = false
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
                    if state.recording {
                        HStack {
                            Image(systemName: "mic.fill").foregroundStyle(.red)
                            Text(t("Listening", "正在听你说"))
                            ProgressView(value: min(Double(state.level) * 12, 1)).frame(width: 100)
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
        .onChange(of: state.selectedTab) { _, _ in
            state.checkModelCacheStatus()
        }
    }

    private var mascot: NSImage {
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "png"), let image = NSImage(contentsOf: url) {
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

    private func statusModule(
        number: Int,
        title: String,
        subtitle: String,
        isReady: Bool,
        isPreparing: Bool,
        targetTab: AppTab
    ) -> some View {
        Button {
            state.selectedTab = targetTab
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .foregroundStyle(isReady ? Color.green : (isPreparing ? Color.blue : Color.orange))
                        .frame(width: 18, height: 18)
                        .background((isReady ? Color.green : (isPreparing ? Color.blue : Color.orange)).opacity(0.15))
                        .clipShape(Circle())

                    Spacer()

                    if isPreparing {
                        ProgressView().controlSize(.small)
                    } else if isReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                    }
                }

                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isReady ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isReady ? Color.green.opacity(0.25) : (isPreparing ? Color.blue.opacity(0.3) : Color.orange.opacity(0.35)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(title): \(subtitle)")
    }

    private var general: some View {
        let permReady = state.micAuthorized && state.axAuthorized
        let speechReady = state.ready || state.isSpeechDownloaded
        let textReady = state.editorReady || state.isEditorDownloaded
        let allReady = permReady && speechReady && textReady

        return VStack(alignment: .leading, spacing: 20) {
            // 0. System Readiness Check
            settingsCard(title: t("System Readiness Check", "当前就绪状态检查")) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        statusModule(
                            number: 1,
                            title: t("Permissions", "系统权限"),
                            subtitle: permReady ? t("Authorized", "已授权") : t("Needs grant", "缺少授权"),
                            isReady: permReady,
                            isPreparing: false,
                            targetTab: .permissions
                        )

                        statusModule(
                            number: 2,
                            title: t("Speech Model", "语音识别"),
                            subtitle: state.speechPreparing ? t("Preparing…", "加载中…") : (speechReady ? t("Ready", "已就绪") : t("Not downloaded", "尚未下载")),
                            isReady: speechReady,
                            isPreparing: state.speechPreparing,
                            targetTab: .speech
                        )

                        statusModule(
                            number: 3,
                            title: t("Text Model", "文本模型"),
                            subtitle: state.editorPreparing ? t("Preparing…", "加载中…") : (textReady ? t("Ready", "已就绪") : t("Not downloaded", "尚未下载")),
                            isReady: textReady,
                            isPreparing: state.editorPreparing,
                            targetTab: .editor
                        )
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if allReady {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text(t("All 3 components ready · System is fully operational for dictation.", "核心组件已全部就绪（3/3）· 按下全局快捷键即可随时听写。"))
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(t("System not fully ready · Please ensure all 3 modules show green checkmarks.", "系统尚未完全就绪：三个模块均需显示绿色对勾方可正常使用，点击未就绪模块可快速配置。"))
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                }
            }

            // 1. Shortcut & Dictation Mode
            settingsCard(title: t("Shortcut & Recording", "快捷键与录音方式")) {
                settingRow(
                    title: t("Trigger key", "触发按键"),
                    subtitle: t("Fn may also trigger the macOS Globe key action.", "Fn 也可能触发 macOS 的地球键功能。")
                ) {
                    Picker("", selection: $state.preferences.useFnKey) {
                        Text(t("Custom shortcut", "自定义快捷键")).tag(false)
                        Text("Fn / 🌐").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(state.recording || state.busy)
                }
                Divider()
                if !state.preferences.useFnKey {
                settingRow(
                    title: t("Dictation Shortcut", "全局快捷键"),
                    subtitle: t("Press anywhere to trigger dictation", "在 macOS 任意应用中直接唤醒语音输入")
                ) {
                    KeyboardShortcuts.Recorder(for: .toggleDictation)
                }
                Divider()
                }
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
                    subtitle: t("Pause and resume when the player state can be verified", "可确认播放器状态时，录音期间暂停并在结束后恢复")
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
            // 1. Model Library & Local Storage Management
            settingsCard(title: t("Local Speech Models & Storage", "本地语音模型列表与存储管理")) {
                VStack(spacing: 14) {
                    ForEach(Array(SpeechModelSpec.allModels.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 {
                            Divider()
                        }

                        let isCached = state.cachedSpeechModelIDs.contains(spec.id)
                        let isDownloadingThis = state.speechPreparing && state.activeDownloadingSpeechModelID == spec.id && !isCached

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(spec.name)
                                            .font(.headline)
                                        Text(spec.quantization)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                        Text(spec.size)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(t(spec.descriptionEn, spec.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Status indicator (Download status only)
                                if isDownloadingThis {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("\(Int(state.speechProgress * 100))%")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                } else if isCached {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 8, height: 8)
                                        Text(t("Downloaded", "已下载"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
                                        Text(t("Not Downloaded", "尚未下载"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Action button
                                if isDownloadingThis {
                                    Button(t("Cancel", "取消")) {
                                        state.cancel()
                                    }
                                    .controlSize(.small)
                                    .accessibilityLabel(t("Cancel", "取消"))
                                } else if isCached {
                                    Button(role: .destructive) {
                                        speechModelToDelete = spec.id
                                        confirmSpeechDelete = true
                                    } label: {
                                        Text(t("Delete Cache…", "删除本地缓存…"))
                                    }
                                    .controlSize(.small)
                                    .disabled(state.busy || state.recording)
                                    .accessibilityLabel(t("Delete Cache…", "删除本地缓存…"))
                                } else {
                                    Button {
                                        state.downloadSpeechModel(id: spec.id)
                                    } label: {
                                        Text(t("Download", "下载"))
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(state.busy || state.recording)
                                    .accessibilityLabel(t("Download", "下载"))
                                }
                            }

                            if isDownloadingThis {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: state.speechProgress)
                                    if !state.speechProgressMessage.isEmpty {
                                        Text(state.speechProgressMessage)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }
            }

            // 2. Active Model & Language Selection Card
            settingsCard(title: t("Speech Recognition Model", "语音识别模型与语言选择")) {
                let downloadedSpecs = SpeechModelSpec.allModels.filter { state.cachedSpeechModelIDs.contains($0.id) }

                if downloadedSpecs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("No Speech Models Downloaded Locally", "本地尚未下载任何语音模型"))
                                .font(.headline)
                            Text(t("Please click 'Download' on a model in the list above. Once downloaded, you can select it here for instant use.", "请在上方模型列表中点击“下载”获取所需模型。下载完成后即可在此处选择生效。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    settingRow(
                        title: t("Active Recognition Model", "当前生效模型"),
                        subtitle: t("On-device acoustic model for speech-to-text", "用于端侧实时语音转文字的声学转录模型")
                    ) {
                        Picker("", selection: Binding(
                            get: { state.preferences.speechModel },
                            set: { newModel in state.selectSpeechModel(id: newModel) }
                        )) {
                            ForEach(downloadedSpecs) { spec in
                                Text("\(spec.name) (\(spec.quantization) · \(spec.size))").tag(spec.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(state.busy || state.recording)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if state.ready {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(t("Model & VAD are loaded in unified memory · Ready for instant dictation.", "声学识别与语音检测模型已载入统一内存 · 随时可用 (快捷键即刻听写)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if state.speechPreparing {
                            ProgressView()
                                .controlSize(.small)
                            Text(t("Loading model into unified memory…", "正在载入统一内存…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(t("Model not loaded into unified memory.", "模型尚未载入统一内存。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(t("Load into Memory", "载入内存")) {
                                state.loadActiveSpeechModel()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel(t("Load into Memory", "载入内存"))
                        }
                        Spacer()
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
            }

            // 3. How Speech Recognition Works Guide
            settingsCard(title: t("How Speech Recognition Works", "语音识别工作机制")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Qwen3-ASR Acoustic Transcription", "Qwen3-ASR 端侧声学识别")).font(.subheadline.bold())
                            Text(t("Runs locally on Apple Neural Engine and GPU via MLX. Accurately transcribes Chinese, English, code terms, and mixed speech with proper punctuation.", "通过 MLX 引擎全本地运行于 Apple 芯片 GPU 与神经引擎。精准识别中英双语、技术术语与混合说话，并自带标点分句。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Silero VAD Voice Activity Detection", "Silero VAD 语音活动检测")).font(.subheadline.bold())
                            Text(t("Ultra-low latency speech boundary detection. Seamlessly isolates speech from background noise and silence with zero external server transmission.", "毫秒级精准检测人声起止时刻，有效过滤环境杂音与静音段，全程 100% 离线，完全保护隐私。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 580)
        .confirmationDialog(t("Delete this speech model from disk?", "从本机删除此语音模型？"), isPresented: $confirmSpeechDelete) {
            Button(t("Delete", "删除"), role: .destructive) {
                if let targetId = speechModelToDelete {
                    state.removeSpeechModel(id: targetId)
                    speechModelToDelete = nil
                } else {
                    state.removeSpeechModel()
                }
            }
        } message: {
            Text(t("Model files will be removed from your disk. You can re-download anytime.", "模型文件将从本机存储中移除，后续需要时可随时重新下载。"))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Model Library & Local Storage Management
            settingsCard(title: t("Local Models & Storage", "本地模型列表与存储管理")) {
                VStack(spacing: 14) {
                    ForEach(Array(TextModelSpec.allModels.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 {
                            Divider()
                        }

                        let isCached = state.cachedTextModelIDs.contains(spec.id)
                        let isDownloadingThis = state.editorPreparing && state.activeDownloadingTextModelID == spec.id && !isCached

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(spec.name)
                                            .font(.headline)
                                        Text(spec.quantization)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                        Text(spec.size)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(t(spec.descriptionEn, spec.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Status indicator (Download status only)
                                if isDownloadingThis {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("\(Int(state.editorProgress * 100))%")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                } else if isCached {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 8, height: 8)
                                        Text(t("Downloaded", "已下载"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
                                        Text(t("Not Downloaded", "尚未下载"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Action button
                                if isDownloadingThis {
                                    Button(t("Cancel", "取消")) {
                                        state.cancel()
                                    }
                                    .controlSize(.small)
                                    .accessibilityLabel(t("Cancel", "取消"))
                                } else if isCached {
                                    Button(role: .destructive) {
                                        textModelToDelete = spec.id
                                        confirmTextDelete = true
                                    } label: {
                                        Text(t("Delete Cache…", "删除本地缓存…"))
                                    }
                                    .controlSize(.small)
                                    .disabled(state.busy || state.recording)
                                    .accessibilityLabel(t("Delete Cache…", "删除本地缓存…"))
                                } else {
                                    Button {
                                        state.downloadTextModel(id: spec.id)
                                    } label: {
                                        Text(t("Download", "下载"))
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(state.busy || state.recording)
                                    .accessibilityLabel(t("Download", "下载"))
                                }
                            }

                            if isDownloadingThis {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: state.editorProgress)
                                    if !state.editorProgressMessage.isEmpty {
                                        Text(state.editorProgressMessage)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }
            }

            // 2. Active Model Selection Card
            settingsCard(title: t("Text Refinement Model", "文本润色模型选择")) {
                let downloadedSpecs = TextModelSpec.allModels.filter { state.cachedTextModelIDs.contains($0.id) }

                if downloadedSpecs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("No Models Downloaded Locally", "本地尚未下载任何文本模型"))
                                .font(.headline)
                            Text(t("Please click 'Download' on a model in the list above. Once downloaded, you can select it here for instant use.", "请在上方模型列表中点击“下载”获取所需模型。下载完成后即可在此处选择生效。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    settingRow(
                        title: t("Active Refinement Model", "当前生效模型"),
                        subtitle: t("Local LLM used for Moderate editing and Rewrite modes", "用于“适度整理”与“完全重写”模式的端侧大语言模型")
                    ) {
                        Picker("", selection: Binding(
                            get: { state.preferences.textModel },
                            set: { newModel in state.selectTextModel(id: newModel) }
                        )) {
                            ForEach(downloadedSpecs) { spec in
                                Text("\(spec.name) (\(spec.quantization) · \(spec.size))").tag(spec.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(state.busy || state.recording)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if state.editorReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(t("Model is loaded in unified memory · Ready for instant zero-latency refinement.", "模型已载入统一内存 · 随时可用 (毫秒级零延迟润色)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if state.editorPreparing {
                            ProgressView()
                                .controlSize(.small)
                            Text(t("Loading model into unified memory…", "正在载入统一内存…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(t("Model not loaded into unified memory.", "模型尚未载入统一内存。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(t("Load into Memory", "载入内存")) {
                                state.loadActiveEditorModel()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel(t("Load into Memory", "载入内存"))
                        }
                        Spacer()
                    }
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
        .confirmationDialog(t("Delete this text model from disk?", "从本机删除此文本模型？"), isPresented: $confirmTextDelete) {
            Button(t("Delete", "删除"), role: .destructive) {
                if let targetId = textModelToDelete {
                    state.removeTextModel(id: targetId)
                    textModelToDelete = nil
                } else {
                    state.removeTextModel()
                }
            }
        } message: {
            Text(t("Model files will be removed from your disk. You can re-download anytime.", "模型文件将从本机存储中移除，后续需要时可随时重新下载。"))
        }
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
                        state.status = state.insertFailure
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

            VStack(alignment: .leading, spacing: 10) {
                Text(t("Diagnostics", "诊断日志")).font(.headline)
                Text(t("Stored only on this Mac. Logs include app identifiers and diagnostic status, but not audio, dictated text, or clipboard contents. Seven files of up to about 1 MB each are retained.", "日志仅保存在本机，包含应用标识和诊断状态，不包含录音、听写文字或剪贴板内容。最多保留 7 个文件，每个约 1 MB。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(t("Show Logs in Finder", "在 Finder 中显示日志")) {
                    do {
                        let url = try DiagnosticLog.shared.readyFile()
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } catch {
                        diagnosticsError = true
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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

                    Text(t("Built with Sparkle, KeyboardShortcuts, LaunchAtLogin, Whisper.cpp, and MLX.", "基于 Sparkle、KeyboardShortcuts、LaunchAtLogin、Whisper.cpp 与 MLX 开源生态构建。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: 560)
        .alert(t("Could not read diagnostic logs", "无法读取诊断日志"), isPresented: $diagnosticsError) {
            Button(t("OK", "好"), role: .cancel) { }
        } message: {
            Text(t("Check that Voice Buddy can write to its local Logs folder.", "请检查 Voice Buddy 是否有权限写入本机日志文件夹。"))
        }
    }
}
