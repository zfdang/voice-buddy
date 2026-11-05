import SwiftUI
import AppKit
import Carbon
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
                Label(t("General", "通用"), systemImage: "slider.horizontal.3").tag(0)
                Label(t("Speech recognition", "语音识别"), systemImage: "waveform").tag(1)
                Label(t("Text model", "文本模型"), systemImage: "text.bubble").tag(2)
                Label(t("Result", "结果"), systemImage: "doc.text").tag(3)
            }.navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(nsImage: mascot).resizable().scaledToFit().frame(width: 50, height: 50)
                        VStack(alignment: .leading) { Text("Voice Buddy").font(.title.bold()); Text(t("Your voice, on your Mac.", "你的声音，在本机变成文字。 ")).foregroundStyle(.secondary) }
                        Spacer()
                    }
                    Text(state.status).accessibilityIdentifier("status").foregroundStyle(.secondary)
                    if state.modelPreparing { HStack { ProgressView(value: state.modelProgress).frame(maxWidth: 300); Button(t("Cancel", "取消")) { state.cancel() } } }
                    else if state.busy && !state.recording { Button(t("Cancel", "取消")) { state.cancel() } }
                    if state.recording {
                        HStack { Image(systemName: "mic.fill").foregroundStyle(.red); Text(t("Listening", "正在听你说")); ProgressView(value: min(Double(state.level) * 12, 1)).frame(width: 100); Button(t("Stop", "结束")) { state.toggle() }; Button(t("Cancel", "取消")) { state.cancel() } }
                    }
                    Divider()
                    switch state.selectedTab {
                    case 0: general
                    case 1: speech
                    case 2: editor
                    default: recovery
                    }
                    Spacer()
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.onChange(of: state.status) { _, _ in if !state.result.isEmpty && !state.recording && !state.busy { state.selectedTab = 3 } }
    }
    private var mascot: NSImage { if let url = Bundle.module.url(forResource: "mascot", withExtension: "png"), let image = NSImage(contentsOf: url) { return image }; return NSImage() }
    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("General", "通用设置")).font(.title2.bold())
            Picker(t("Interface language", "界面语言"), selection: $state.preferences.interfaceLanguage) { Text(t("System", "跟随系统")).tag("system"); Text("English").tag("en"); Text("简体中文").tag("zh") }
            Picker(t("Microphone", "麦克风输入"), selection: $state.preferences.microphoneUID) {
                Text(t("System default", "系统默认")).tag("")
                ForEach(AudioDevices.devices(), id: \.0) { device in Text(device.1).tag(device.0) }
            }
            Picker(t("Refinement", "文字整理力度"), selection: $state.preferences.refinement) {
                Text(t("Original", "原文")).tag(Refinement.original); Text(t("Light", "轻微整理")).tag(Refinement.light); Text(t("Moderate", "适度整理")).tag(Refinement.moderate); Text(t("Rewrite", "完全重写")).tag(Refinement.rewrite)
            }
            Picker(t("Recording mode", "录音模式"), selection: Binding(get: { state.preferences.holdToTalk ?? true }, set: { state.preferences.holdToTalk = $0 })) {
                Text(t("Hold to talk", "按住说话")).tag(true); Text(t("Press to start / stop", "按键切换录音")).tag(false)
            }.disabled(state.recording || state.busy)
            Toggle(t("Sound feedback", "提示音"), isOn: $state.preferences.sounds)
            Toggle(t("Insert automatically when safe", "确认安全时自动插入"), isOn: $state.preferences.autoInsert)
            HStack { Text(t("Shortcut", "快捷键")); ShortcutCapture(capturing: $capturingShortcut, keyCode: state.preferences.shortcutKeyCode, modifiers: state.preferences.shortcutModifiers) { code, mods in state.registerHotkey(keyCode: code, modifiers: mods) }; Text(capturingShortcut ? t("Press a shortcut; Escape cancels", "按下组合键；Esc 取消") : t("Click to change", "点击更改")).foregroundStyle(.secondary) }
            Button(state.recording ? t("Stop", "结束听写") : t("Start dictation", "开始听写")) { state.toggle() }.disabled(state.busy)
        }.frame(maxWidth: 550)
    }
    private var speech: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("Speech recognition", "语音识别")).font(.title2.bold())
            Picker(t("Recognition model", "识别模型"), selection: $state.preferences.speechModel) {
                Text("Qwen3-ASR 0.6B").tag("mlx-community/Qwen3-ASR-0.6B-8bit")
                Text("Qwen3-ASR 1.7B (16 GB+)").tag("mlx-community/Qwen3-ASR-1.7B-8bit")
            }.disabled(state.busy || state.recording).onChange(of: state.preferences.speechModel) { _, _ in state.ready = false }
            Picker(t("Spoken language", "识别语言"), selection: $state.preferences.speechLanguage) {
                Text(t("Automatic", "自动识别 / 混说")).tag("auto"); Text("中文").tag("Chinese"); Text("English").tag("English"); Text("Français").tag("French")
            }
            Text(t("Models download from Hugging Face on first preparation. Recognition runs locally.", "首次准备时从 Hugging Face 下载模型，识别在本机运行。 ")).foregroundStyle(.secondary)
            Button(state.ready ? t("Reload model", "重新加载模型") : t("Download / prepare model", "下载 / 准备模型")) { state.prepareSpeech() }.disabled(state.busy)
            Button(t("Delete model…", "删除模型…")) { confirmSpeechDelete = true }.disabled(state.busy || state.recording)
                .confirmationDialog(t("Delete this speech model?", "删除当前语音模型？"), isPresented: $confirmSpeechDelete) { Button(t("Delete", "删除"), role: .destructive) { state.removeSpeechModel() } }
            Button(t("Grant Accessibility", "授予辅助功能权限")) { let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary; _ = AXIsProcessTrustedWithOptions(options) }
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("Text model", "文本模型")).font(.title2.bold())
            Text("Qwen 3.5 0.8B · MLX")
            Text(t("Required only for moderate editing and rewrite. Downloads on first preparation.", "仅适度整理和完全重写需要；首次准备时下载。 ")).foregroundStyle(.secondary)
            Button(t("Delete text model…", "删除文本模型…")) { confirmTextDelete = true }.disabled(state.busy || state.recording)
                .confirmationDialog(t("Delete the text model?", "删除文本模型？"), isPresented: $confirmTextDelete) { Button(t("Delete", "删除"), role: .destructive) { state.removeTextModel() } }
            Button(state.editorReady ? t("Reload model", "重新加载模型") : t("Download / prepare model", "下载 / 准备模型")) { state.prepareEditor() }.disabled(state.busy)
        }
    }
    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Result", "识别结果")).font(.title2.bold())
            Text(t("Review before copying or inserting.", "请检查后复制或插入。 ")).foregroundStyle(.secondary)
            TextEditor(text: $state.result).frame(minHeight: 160).border(.quaternary)
            HStack { Button(t("Copy", "复制")) { state.copyResult() }; Button(t("Show original", "查看原文")) { state.result = state.original }; Button(t("Insert", "插入")) { if !state.insertIfSafe(state.result) { state.status = t("Return to the original field and copy manually.", "请回到原输入框并手动粘贴。") } } }
        }
    }
}

struct ShortcutCapture: NSViewRepresentable {
    @Binding var capturing: Bool
    var keyCode: UInt32
    var modifiers: UInt32
    var onCapture: (UInt32, UInt32) -> Bool
    func makeNSView(context: Context) -> ShortcutButton { let view = ShortcutButton(); view.onCapture = onCapture; view.onState = { capturing = $0 }; return view }
    func updateNSView(_ view: ShortcutButton, context: Context) { view.onCapture = onCapture; view.onState = { capturing = $0 }; if !capturing { view.title = ShortcutButton.display(code: keyCode, modifiers: modifiers) } }
}
final class ShortcutButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Bool)?; var onState: ((Bool) -> Void)?
    private var monitor: Any?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); bezelStyle = .rounded; target = self; action = #selector(begin) }
    required init?(coder: NSCoder) { nil }
    @objc private func begin() {
        guard monitor == nil else { return }; title = "…"; onState?(true); window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.end(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask); var mods: UInt32 = 0
            if flags.contains(.command) { mods |= UInt32(cmdKey) }; if flags.contains(.option) { mods |= UInt32(optionKey) }; if flags.contains(.control) { mods |= UInt32(controlKey) }; if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            guard mods != 0 else { return nil }
            _ = self.onCapture?(UInt32(event.keyCode), mods); self.end(); return nil
        }
    }
    private func end() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; onState?(false) }
    static func display(code: UInt32, modifiers: UInt32) -> String {
        var text = ""; if modifiers & UInt32(controlKey) != 0 { text += "⌃" }; if modifiers & UInt32(optionKey) != 0 { text += "⌥" }; if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }; if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        let names: [UInt32:String] = [49:"Space", 9:"V", 2:"D", 8:"C", 15:"R"]
        return text + " " + (names[code] ?? "Key \(code)")
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
