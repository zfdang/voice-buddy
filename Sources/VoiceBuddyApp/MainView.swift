import SwiftUI
import AppKit
import Carbon
import AVFoundation
import VoiceBuddyCore

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var capturingShortcut = false
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
            }.navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(nsImage: mascot).resizable().scaledToFit().frame(width: 50, height: 50)
                        VStack(alignment: .leading) {
                            Text("Voice Buddy").font(.title.bold())
                            Text(t("Your voice, on your Mac.", "你的声音，在本机变成文字。 ")).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text(state.status).accessibilityIdentifier("status").foregroundStyle(.secondary)
                    if state.modelPreparing {
                        HStack {
                            ProgressView(value: state.modelProgress).frame(maxWidth: 300)
                            Button(t("Cancel", "取消")) { state.cancel() }
                        }
                    } else if state.busy && !state.recording {
                        Button(t("Cancel", "取消")) { state.cancel() }
                    }
                    if state.recording {
                        HStack {
                            Image(systemName: "mic.fill").foregroundStyle(.red)
                            Text(t("Listening", "正在听你说"))
                            ProgressView(value: min(Double(state.level) * 12, 1)).frame(width: 100)
                            Button(t("Stop", "结束")) { state.toggle() }
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

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("General", "通用设置")).font(.title2.bold())
            Picker(t("Interface language", "界面语言"), selection: $state.preferences.interfaceLanguage) {
                Text(t("System", "跟随系统")).tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh")
            }
            Picker(t("Microphone", "麦克风输入"), selection: $state.preferences.microphoneUID) {
                Text(t("System default", "系统默认")).tag("")
                ForEach(AudioDevices.devices(), id: \.0) { device in Text(device.1).tag(device.0) }
            }
            Picker(t("Refinement", "文字整理力度"), selection: $state.preferences.refinement) {
                Text(t("Original", "原文")).tag(Refinement.original)
                Text(t("Light", "轻微整理")).tag(Refinement.light)
                Text(t("Moderate", "适度整理")).tag(Refinement.moderate)
                Text(t("Rewrite", "完全重写")).tag(Refinement.rewrite)
            }
            Picker(t("Recording mode", "录音模式"), selection: Binding(get: { state.preferences.holdToTalk ?? true }, set: { state.preferences.holdToTalk = $0 })) {
                Text(t("Hold to talk", "按住说话")).tag(true)
                Text(t("Press to start / stop", "按键切换录音")).tag(false)
            }.disabled(state.recording || state.busy)
            Toggle(t("Sound feedback", "提示音"), isOn: $state.preferences.sounds)
            Toggle(t("Insert automatically when safe", "确认安全时自动插入"), isOn: $state.preferences.autoInsert)
            HStack {
                Text(t("Shortcut", "快捷键"))
                ShortcutCapture(capturing: $capturingShortcut, keyCode: state.preferences.shortcutKeyCode, modifiers: state.preferences.shortcutModifiers) { code, mods in
                    state.registerHotkey(keyCode: code, modifiers: mods)
                }
                Text(capturingShortcut ? t("Press a shortcut; Escape cancels", "按下组合键；Esc 取消") : t("Click to change", "点击更改")).foregroundStyle(.secondary)
            }
            Button(state.recording ? t("Stop", "结束听写") : t("Start dictation", "开始听写")) { state.toggle() }.disabled(state.busy)
        }.frame(maxWidth: 550)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Permissions Check", "系统权限检查")).font(.title2.bold())
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
        VStack(alignment: .leading, spacing: 18) {
            Text(t("Speech recognition", "语音识别")).font(.title2.bold())
            Picker(t("Recognition model", "识别模型"), selection: $state.preferences.speechModel) {
                Text("Qwen3-ASR 0.6B").tag("mlx-community/Qwen3-ASR-0.6B-8bit")
                Text("Qwen3-ASR 1.7B (16 GB+)").tag("mlx-community/Qwen3-ASR-1.7B-8bit")
            }.disabled(state.busy || state.recording).onChange(of: state.preferences.speechModel) { _, _ in state.ready = false }
            Picker(t("Spoken language", "识别语言"), selection: $state.preferences.speechLanguage) {
                Text(t("Automatic", "自动识别 / 混说")).tag("auto")
                Text("中文").tag("Chinese")
                Text("English").tag("English")
                Text("Français").tag("French")
            }
            Text(t("Models download from Hugging Face on first preparation. Recognition runs locally.", "首次准备时从 Hugging Face 下载模型，识别在本机运行。 ")).foregroundStyle(.secondary)
            Button(state.ready ? t("Reload model", "重新加载模型") : t("Download / prepare model", "下载 / 准备模型")) { state.prepareSpeech() }.disabled(state.busy)
            Button(t("Delete model…", "删除模型…")) { confirmSpeechDelete = true }.disabled(state.busy || state.recording)
                .confirmationDialog(t("Delete this speech model?", "删除当前语音模型？"), isPresented: $confirmSpeechDelete) {
                    Button(t("Delete", "删除"), role: .destructive) { state.removeSpeechModel() }
                }
            Divider()
            Button(t("View Permissions…", "查看权限检查…")) {
                state.selectedTab = .permissions
            }.accessibilityLabel(t("View Permissions…", "查看权限检查…"))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("Text model", "文本模型")).font(.title2.bold())
            Text("Qwen 3.5 0.8B · MLX")
            Text(t("Required only for moderate editing and rewrite. Downloads on first preparation.", "仅适度整理和完全重写需要；首次准备时下载。 ")).foregroundStyle(.secondary)
            Button(t("Delete text model…", "删除文本模型…")) { confirmTextDelete = true }.disabled(state.busy || state.recording)
                .confirmationDialog(t("Delete the text model?", "删除文本模型？"), isPresented: $confirmTextDelete) {
                    Button(t("Delete", "删除"), role: .destructive) { state.removeTextModel() }
                }
            Button(state.editorReady ? t("Reload model", "重新加载模型") : t("Download / prepare model", "下载 / 准备模型")) { state.prepareEditor() }.disabled(state.busy)
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Result", "识别结果")).font(.title2.bold())
            Text(t("Review before copying or inserting.", "请检查后复制或插入。 ")).foregroundStyle(.secondary)
            TextEditor(text: $state.result).frame(minHeight: 160).border(.quaternary)
            HStack {
                Button(t("Copy", "复制")) { state.copyResult() }.accessibilityLabel(t("Copy", "复制"))
                Button(t("Show original", "查看原文")) { state.result = state.original }.accessibilityLabel(t("Show original", "查看原文"))
                Button(t("Insert", "插入")) {
                    if !state.insertIfSafe(state.result) {
                        state.status = t("Return to the original field and copy manually.", "请回到原输入框并手动粘贴。")
                    }
                }.accessibilityLabel(t("Insert", "插入"))
            }
        }
    }
}

struct ShortcutCapture: NSViewRepresentable {
    @Binding var capturing: Bool
    var keyCode: UInt32
    var modifiers: UInt32
    var onCapture: (UInt32, UInt32) -> Bool
    func makeNSView(context: Context) -> ShortcutButton {
        let view = ShortcutButton()
        view.onCapture = onCapture
        view.onState = { capturing = $0 }
        return view
    }
    func updateNSView(_ view: ShortcutButton, context: Context) {
        view.onCapture = onCapture
        view.onState = { capturing = $0 }
        if !capturing {
            view.title = ShortcutButton.display(code: keyCode, modifiers: modifiers)
        }
    }
}

final class ShortcutButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Bool)?
    var onState: ((Bool) -> Void)?
    private var monitor: Any?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(begin)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func begin() {
        guard monitor == nil else { return }
        title = "…"
        onState?(true)
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.end(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            guard mods != 0 else { return nil }
            _ = self.onCapture?(UInt32(event.keyCode), mods)
            self.end()
            return nil
        }
    }
    private func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onState?(false)
    }
    static func display(code: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        let names: [UInt32:String] = [49:"Space", 9:"V", 2:"D", 8:"C", 15:"R"]
        return text + " " + (names[code] ?? "Key \(code)")
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
