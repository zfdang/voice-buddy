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
    @State private var showPromptPreview = false
    @State private var copiedPromptTip = false
    @State private var resultTestMode: Refinement?
    @State private var resultActionStatus = ""
    private func t(_ en: String, _ zh: String) -> String { state.label(en, zh) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 108)
            Color(nsColor: .separatorColor)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state.recording {
                        HStack {
                            Image(systemName: "mic.fill").foregroundStyle(.red)
                            Text(t("Listening", "正在听你说"))
                            ProgressView(value: min(Double(state.level) * 12, 1)).frame(width: 100)
                            Button(t("Cancel", "取消")) { state.cancel() }
                        }
                        Divider()
                    }
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
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            state.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
        .onChange(of: state.selectedTab) { _, _ in
            state.checkModelCacheStatus()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App Branding at the top of the sidebar
            VStack(spacing: 6) {
                Image(nsImage: mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("Voice Buddy")
                    .font(.system(size: 13, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        sidebarButton(tab)
                    }
                }
                .padding(.top, 6)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarButton(_ tab: AppTab) -> some View {
        let isSelected = state.selectedTab == tab
        return Button {
            state.selectedTab = tab
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tabSystemImage(tab))
                    .font(.system(size: 21, weight: .semibold))
                Text(tabTitle(tab))
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func tabSystemImage(_ tab: AppTab) -> String {
        switch tab {
        case .general: return "slider.horizontal.3"
        case .permissions: return "checkmark.shield"
        case .speech: return "waveform"
        case .editor: return "text.bubble"
        case .recovery: return "doc.text"
        case .about: return "info.circle"
        }
    }

    private func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .general: return t("General", "通用")
        case .permissions: return t("Permissions", "权限检查")
        case .speech: return t("Speech", "语音识别")
        case .editor: return t("Text model", "文本模型")
        case .recovery: return t("Result", "结果")
        case .about: return t("About", "关于")
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
        let speechReady = state.asrReady || state.isSpeechDownloaded
        let textReady = !state.preferences.refinement.needsModel || state.editorReady || state.isEditorDownloaded
        let allReady = permReady && speechReady && textReady

        let isCurrentSpeechDownloading = state.downloadingSpeechModelIDs.contains(state.preferences.speechModel)
        let isCurrentTextDownloading = state.downloadingTextModelIDs.contains(state.preferences.textModel)

        let speechSubtitle: String = {
            if state.isActivatingSpeechModel {
                return state.preferences.speechModel.contains("whisper")
                    ? t("Loading (1-2 mins on first run)…", "载入中 (首次编译约1~2分钟)…")
                    : t("Loading into memory…", "载入内存中…")
            }
            if isCurrentSpeechDownloading { return t("Downloading…", "下载中…") }
            if state.asrReady { return t("Ready", "已就绪") }
            if state.isSpeechDownloaded { return t("Downloaded", "已下载") }
            return t("Not downloaded", "尚未下载")
        }()

        let textSubtitle: String = {
            if !state.preferences.refinement.needsModel {
                return t("Light mode (No LLM needed)", "轻度调整 (无需大模型)")
            }
            if state.isActivatingTextModel { return t("Loading into memory…", "载入内存中…") }
            if isCurrentTextDownloading { return t("Downloading…", "下载中…") }
            if state.editorReady { return t("Ready", "已就绪") }
            if state.isEditorDownloaded { return t("Downloaded", "已下载") }
            return t("Not downloaded", "尚未下载")
        }()

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
                            subtitle: speechSubtitle,
                            isReady: speechReady,
                            isPreparing: state.isActivatingSpeechModel || isCurrentSpeechDownloading,
                            targetTab: .speech
                        )

                        statusModule(
                            number: 3,
                            title: t("Text Model", "文本模型"),
                            subtitle: textSubtitle,
                            isReady: textReady,
                            isPreparing: state.preferences.refinement.needsModel && (state.isActivatingTextModel || isCurrentTextDownloading),
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

                    let hasBackgroundDownloads = (!isCurrentSpeechDownloading && !state.downloadingSpeechModelIDs.isEmpty) || (!isCurrentTextDownloading && !state.downloadingTextModelIDs.isEmpty)
                    if hasBackgroundDownloads {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(t("Background models are downloading. This does not affect active dictation.", "后台正在下载其他模型，不影响当前快捷键听写。"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 2)
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
                        Text(t("Light", "轻度")).tag(Refinement.light)
                        Text(t("Moderate", "适度")).tag(Refinement.balanced)
                        Text(t("Deep", "深度")).tag(Refinement.moderate)
                        Text(t("Professional Rewrite", "专业改写")).tag(Refinement.rewrite)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if state.preferences.refinement != .original, let prompt = RefinementPrompts.prompt(for: state.preferences.refinement) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPromptPreview.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showPromptPreview ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Image(systemName: "text.bubble")
                                    .foregroundStyle(.secondary)
                                Text(t("View System Prompt", "查看当前级别的 System Prompt"))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showPromptPreview {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(t("System Prompt for active level (Read-Only Preview)", "当前级别生效的 System Prompt（只读预览）"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(prompt, forType: .string)
                                        copiedPromptTip = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            copiedPromptTip = false
                                        }
                                    }) {
                                        Label(copiedPromptTip ? t("Copied", "已复制") : t("Copy Prompt", "复制提示词"),
                                              systemImage: copiedPromptTip ? "checkmark" : "doc.on.doc")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                ScrollView {
                                    Text(prompt)
                                        .font(.system(.caption2, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .padding(8)
                                }
                                .frame(height: 140)
                                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .padding(.top, 8)
                            .padding(.leading, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.top, 4)
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
                        let isDownloadingThis = state.downloadingSpeechModelIDs.contains(spec.id)
                        let progressVal = state.speechDownloadProgress[spec.id] ?? 0
                        let progressMsg = state.speechDownloadMessages[spec.id] ?? ""

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 12) {
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
                                        HStack(spacing: 2) {
                                            Image(systemName: "bolt.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.yellow)
                                            Text(spec.latency)
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.1))
                                        .clipShape(Capsule())
                                    }
                                    Text(t(spec.descriptionEn, spec.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 16)

                                // Status indicator & Action button
                                HStack(spacing: 10) {
                                    if spec.id == "apple-speech" {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(.green)
                                            Text(t("Built-in", "系统内置"))
                                                .font(.caption.bold())
                                                .foregroundStyle(.green)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Text(t("Free", "免下载"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 90)
                                    } else if isDownloadingThis {
                                        HStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text("\(Int(progressVal * 100))%")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(t("Cancel", "取消")) {
                                            state.cancelSpeechDownload(id: spec.id)
                                        }
                                        .controlSize(.small)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Cancel", "取消"))
                                    } else if isCached {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.green).frame(width: 8, height: 8)
                                            Text(t("Downloaded", "已下载"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(role: .destructive) {
                                            speechModelToDelete = spec.id
                                            confirmSpeechDelete = true
                                        } label: {
                                            Text(t("Delete Cache…", "删除本地缓存…"))
                                        }
                                        .controlSize(.small)
                                        .disabled(state.busy || state.recording)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Delete Cache…", "删除本地缓存…"))
                                    } else {
                                        HStack(spacing: 4) {
                                            Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
                                            Text(t("Not Downloaded", "尚未下载"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        if isDownloadingThis {
                                            Button(role: .destructive) {
                                                state.cancelSpeechDownload(id: spec.id)
                                            } label: {
                                                Text(t("Cancel", "取消"))
                                            }
                                            .controlSize(.small)
                                            .buttonStyle(.bordered)
                                            .frame(minWidth: 90)
                                            .accessibilityLabel(t("Cancel Download", "取消下载"))
                                        } else {
                                            Button {
                                                state.downloadSpeechModel(id: spec.id)
                                            } label: {
                                                Text(t("Download", "下载"))
                                            }
                                            .controlSize(.small)
                                            .buttonStyle(.borderedProminent)
                                            .disabled(state.busy || state.recording)
                                            .frame(minWidth: 90)
                                            .accessibilityLabel(t("Download", "下载"))
                                        }
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }

                            if isDownloadingThis {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: progressVal)
                                    if !progressMsg.isEmpty {
                                        Text(progressMsg)
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

                    // Active Model Characteristics & Evaluation Card
                    if let activeSpec = SpeechModelSpec.allModels.first(where: { $0.id == state.preferences.speechModel }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(t("Model Profile & Evaluation", "当前模型特点与性能评估"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(0..<5) { star in
                                        Image(systemName: star < activeSpec.speedRating ? "bolt.fill" : "bolt")
                                            .font(.caption2)
                                            .foregroundStyle(star < activeSpec.speedRating ? .yellow : .secondary)
                                    }
                                    Text(activeSpec.latency)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                                GridRow {
                                    Text(t("Languages:", "主攻语种："))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(t(activeSpec.languagesEn, activeSpec.languagesZh))
                                        .font(.caption2.bold())
                                }
                                GridRow {
                                    Text(t("Evaluation:", "效果打分："))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(t(activeSpec.accuracyScoreEn, activeSpec.accuracyScore))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                }
                                GridRow {
                                    Text(t("Footprint:", "显存占用："))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(activeSpec.memoryUsage) · \(activeSpec.size) (\(activeSpec.quantization))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                GridRow {
                                    Text(t("Best For:", "适用场景："))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(t(activeSpec.bestForEn, activeSpec.bestForZh))
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                }
                            }
                            if activeSpec.id.contains("whisper") {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(t("First load compiles to Apple Neural Engine (~1–2 mins, once only). Instant thereafter.", "提示：首次加载需系统神经引擎编译（约需 1~2 分钟，仅执行一次），后续启动即可秒开。"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if state.asrReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(t("Model & VAD are loaded in unified memory · Ready for instant dictation.", "声学识别与语音检测模型已载入统一内存 · 随时可用 (快捷键即刻听写)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if state.isActivatingSpeechModel {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Loading model into unified memory…", "正在载入统一内存…"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                if state.preferences.speechModel.contains("whisper") {
                                    Text(t("First-time load requires Neural Engine compilation (~1–2 minutes, one-time only). Subsequent launches will be instant.", "首次加载需经由 Apple Neural Engine 硬件编译（约需 1~2 分钟，仅需编译一次），后续秒开，请稍候…"))
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(t("Allocating memory and initializing neural weights…", "正在分配统一内存并初始化权重…"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
                            Text(t("Automatic / Mixed", "自动识别 / 混说")).tag("auto")
                            Text("中文 (普通话)").tag("Chinese")
                            Text("粵語 (Cantonese)").tag("Cantonese")
                            Text("English").tag("English")
                            Text("日本語 (Japanese)").tag("Japanese")
                            Text("한국어 (Korean)").tag("Korean")
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
                            Text(t("Multi-Engine On-Device Transcription", "多引擎端侧声学识别系统")).font(.subheadline.bold())
                            Text(t("Voice Buddy supports 4 distinct model architectures tailored to your hardware and workflows: Qwen3-ASR (MLX flagship for Chinese & Chinglish), Whisper Large-v3 Turbo (CoreML 90+ languages), SenseVoice Small (FunASR sub-100ms instant response), and Apple Speech (0 MB built-in instant ready).", "Voice Buddy 支持 4 类特色声学引擎满足不同硬件与场景需求：Qwen3-ASR（MLX 旗舰中英混说）、Whisper Large-v3 Turbo（CoreML 全球 90+ 语言）、SenseVoice Small（阿里 FunASR 毫秒级极速响应）、Apple Speech（macOS 系统内置 0 下载即用）。")).font(.caption).foregroundStyle(.secondary)
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
        .frame(maxWidth: 680)
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
                        let isDownloadingThis = state.downloadingTextModelIDs.contains(spec.id)
                        let progressVal = state.textDownloadProgress[spec.id] ?? 0
                        let progressMsg = state.textDownloadMessages[spec.id] ?? ""

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

                                Spacer(minLength: 16)

                                // Status indicator & Action button
                                HStack(spacing: 10) {
                                    if isDownloadingThis {
                                        HStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text("\(Int(progressVal * 100))%")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(t("Cancel", "取消")) {
                                            state.cancelTextDownload(id: spec.id)
                                        }
                                        .controlSize(.small)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Cancel", "取消"))
                                    } else if isCached {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.green).frame(width: 8, height: 8)
                                            Text(t("Downloaded", "已下载"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(role: .destructive) {
                                            textModelToDelete = spec.id
                                            confirmTextDelete = true
                                        } label: {
                                            Text(t("Delete Cache…", "删除本地缓存…"))
                                        }
                                        .controlSize(.small)
                                        .disabled(state.busy || state.recording)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Delete Cache…", "删除本地缓存…"))
                                    } else {
                                        HStack(spacing: 4) {
                                            Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
                                            Text(t("Not Downloaded", "尚未下载"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        if isDownloadingThis {
                                            Button(role: .destructive) {
                                                state.cancelTextDownload(id: spec.id)
                                            } label: {
                                                Text(t("Cancel", "取消"))
                                            }
                                            .controlSize(.small)
                                            .buttonStyle(.bordered)
                                            .frame(minWidth: 90)
                                            .accessibilityLabel(t("Cancel Download", "取消下载"))
                                        } else {
                                            Button {
                                                state.downloadTextModel(id: spec.id)
                                            } label: {
                                                Text(t("Download", "下载"))
                                            }
                                            .controlSize(.small)
                                            .buttonStyle(.borderedProminent)
                                            .disabled(state.busy || state.recording)
                                            .frame(minWidth: 90)
                                            .accessibilityLabel(t("Download", "下载"))
                                        }
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }

                            if isDownloadingThis {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: progressVal)
                                    if !progressMsg.isEmpty {
                                        Text(progressMsg)
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
                        subtitle: t("Local LLM used for all refinement modes except Original", "用于轻度、适度、深度和专业改写的端侧大语言模型")
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
                        } else if state.isActivatingTextModel {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Loading model into unified memory…", "正在载入统一内存…"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                Text(t("Mapping unified memory weights, please wait…", "正在映射统一内存权重，请稍候…"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !state.preferences.refinement.needsModel {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(t("Current mode is Original (no text model required, so not loaded into memory).", "当前选择的是原文模式，不需要使用文本模型，因此未载入内存。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(t("Load Anyway", "按需预载入")) {
                                state.loadActiveEditorModel()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel(t("Load Anyway", "按需预载入"))
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(t("Model not loaded into unified memory.", "当前润色模式需要大模型，但尚未载入统一内存。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(t("Load into Memory", "载入内存")) {
                                state.loadActiveEditorModel()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
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
                            Text(t("Original mode", "原文模式")).font(.subheadline.bold())
                            Text(t("Outputs raw speech recognition results directly without loading LLM, providing lightning-fast zero-overhead dictation.", "直接输出语音识别 ASR 原始结果，完全不加载大模型，零内存额外消耗。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Light, Moderate, Deep & Professional Rewrite", "轻度、适度、深度与专业改写模式")).font(.subheadline.bold())
                            Text(t("Run 100% locally via Apple Silicon unified memory to polish speech, fix homophone errors, remove oral fillers, or reconstruct formal lists. If the text model is ever unavailable, the system automatically degrades gracefully to inputting the original transcript.", "在 Apple 统一内存上本地调用轻量端侧大模型，进行同音纠错、口癖过滤、语病自改与条理化重构。全程 100% 离线隐私。若大模型尚未就绪或遇到异常，系统将自动优雅降级，直接输入识别原文，绝不耽误输入。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 680)
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

    private func refinementName(_ mode: Refinement) -> String {
        switch mode {
        case .original: return t("Original", "原文")
        case .light: return t("Light", "轻度")
        case .balanced: return t("Moderate", "适度")
        case .moderate: return t("Deep", "深度")
        case .rewrite: return t("Professional Rewrite", "专业改写")
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Direct Speech Recognition Output (Raw)
            settingsCard(title: t("Direct Speech Recognition (Original)", "原始识别结果 (未修饰原文)")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Raw transcript directly produced by the speech recognition model without post-processing.", "由语音识别模型直接输出的初始文本，未经过标点规整或大模型润色。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(state.original.isEmpty ? t("No speech input recorded yet.", "尚未录制任何语音输入。") : state.original)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(state.original.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(minHeight: 80, maxHeight: 140)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.original, forType: .string)
                            state.status = t("Original text copied", "原文已复制")
                        } label: {
                            Label(t("Copy Original", "复制原文"), systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                        .disabled(state.original.isEmpty)
                        .accessibilityLabel(t("Copy Original", "复制原文"))
                    }
                }
            }

            // 2. Refined & Optimized Output
            settingsCard(title: t("Refined & Optimized Output", "优化润色结果 (最终文本)")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Use the current text model to compare refinement levels on the same original transcript.", "使用当前文本模型和同一份原始识别文本，对比不同整理程度的输出效果。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let model = TextModelSpec.allModels.first(where: { $0.id == state.preferences.textModel }) {
                        Text(t("Current model: ", "当前模型：") + model.name + " · " + model.quantization)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Picker(t("Refinement Level", "整理程度"), selection: Binding(
                            get: { resultTestMode ?? state.preferences.refinement },
                            set: { resultTestMode = $0 }
                        )) {
                            ForEach(Refinement.allCases) { mode in
                                Text(refinementName(mode) + (mode == state.preferences.refinement ? t(" (Default)", "（默认）") : ""))
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(state.testingRefinement)
                        Button(t("Test", "测试")) {
                            let mode = resultTestMode ?? state.preferences.refinement
                            resultActionStatus = ""
                            Task { await state.testRefinement(mode: mode) }
                        }
                        .disabled(state.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.testingRefinement || state.busy || state.recording)
                    }
                    HStack {
                        if state.testingRefinement { ProgressView().controlSize(.small) }
                        Text(state.refinementTestStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !state.refinementTestSummary.isEmpty {
                        Text(state.refinementTestSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $state.result)
                        .disabled(state.testingRefinement)
                        .font(.system(.body, design: .default))
                        .frame(minHeight: 110, maxHeight: 180)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    HStack(spacing: 12) {
                        Button {
                            state.copyResult()
                            resultActionStatus = state.status
                        } label: {
                            Label(t("Copy Result", "复制润色结果"), systemImage: "doc.on.clipboard")
                        }
                        .controlSize(.small)
                        .disabled(state.result.isEmpty || state.testingRefinement)
                        .accessibilityLabel(t("Copy Result", "复制润色结果"))

                        Button {
                            if state.insertIfSafe(state.result) {
                                resultActionStatus = t("Insertion queued", "已安排插入")
                            } else {
                                state.status = state.insertFailure
                                resultActionStatus = state.insertFailure
                            }
                        } label: {
                            Label(t("Insert into Active App", "直接插入光标处"), systemImage: "arrow.down.doc")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(state.result.isEmpty || state.testingRefinement)
                        .accessibilityLabel(t("Insert into Active App", "直接插入光标处"))

                        Spacer()
                        if !resultActionStatus.isEmpty {
                            Text(resultActionStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
                Text(t("Stored only on this Mac. Logs include app identifiers, microphone names, and diagnostic status, but not audio, dictated text, or clipboard contents. Seven files of up to about 1 MB each are retained.", "日志仅保存在本机，包含应用标识、麦克风名称和诊断状态，不包含录音、听写文字或剪贴板内容。最多保留 7 个文件，每个约 1 MB。"))
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
                            Label(t("Official Website", "官方网站与发布页"), systemImage: "globe")
                            Spacer()
                            Link("myvoicebuddy.com", destination: URL(string: "https://myvoicebuddy.com")!)
                        }
                        Divider()
                        HStack {
                            Label(t("Releases & Downloads", "最新发布与下载"), systemImage: "shippingbox")
                            Spacer()
                            Link(t("Visit Website", "访问主页"), destination: URL(string: "https://myvoicebuddy.com")!)
                        }
                        Divider()
                        HStack {
                            Label("GitHub Repository", systemImage: "link")
                            Spacer()
                            Link("github.com/zfdang/voice-buddy", destination: URL(string: "https://github.com/zfdang/voice-buddy")!)
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
