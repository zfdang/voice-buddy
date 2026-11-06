import AppKit
import SwiftUI

// MARK: - Live Transcript State & Model

public struct LiveTranscriptState: Equatable, Sendable {
    public var confirmedText: String = ""
    public var correctionOld: String? = nil
    public var correctionNew: String? = nil
    public var streamingText: String = ""

    public var isCorrecting: Bool {
        !(correctionOld ?? "").isEmpty || !(correctionNew ?? "").isEmpty
    }

    public var isEmpty: Bool {
        confirmedText.isEmpty && !isCorrecting && streamingText.isEmpty
    }

    public mutating func clear() {
        confirmedText = ""
        correctionOld = nil
        correctionNew = nil
        streamingText = ""
    }
}

// MARK: - Diffing & Stream Tracker

@MainActor
final class TranscriptStreamTracker {
    var currentState = LiveTranscriptState()
    private var previousRaw = ""
    private var mergeTimer: Timer?
    var onUpdate: (@MainActor (LiveTranscriptState) -> Void)?

    func reset() {
        mergeTimer?.invalidate()
        mergeTimer = nil
        previousRaw = ""
        currentState.clear()
    }

    func update(rawText: String) -> LiveTranscriptState {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return currentState }
        guard trimmed != previousRaw else { return currentState }

        let old = previousRaw
        previousRaw = trimmed

        if old.isEmpty {
            let tokens = tokenizeText(trimmed)
            if tokens.count <= 2 {
                currentState.confirmedText = ""
                currentState.streamingText = trimmed
            } else {
                let splitIdx = max(1, tokens.count - 2)
                currentState.confirmedText = tokens[0..<splitIdx].joined()
                currentState.streamingText = tokens[splitIdx...].joined()
            }
            return currentState
        }

        let prefix = longestCommonPrefix(old, trimmed)

        // Case 1: Pure Append (old string is a prefix of trimmed)
        if prefix == old {
            let tokens = tokenizeText(trimmed)
            let splitIdx = max(1, tokens.count - 2)
            currentState.confirmedText = tokens[0..<splitIdx].joined()
            currentState.streamingText = tokens[splitIdx...].joined()
            return currentState
        }

        // Case 2: Divergence / Inline Correction detected!
        let oldRemainder = String(old.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        let newRemainder = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)

        if !oldRemainder.isEmpty && !newRemainder.isEmpty {
            let delimiters = [" and ", " then ", " but ", " with ", " 并且 ", " 然后 ", " 而且 ", "，", ", "]
            var corrPart = newRemainder
            var streamPart = ""
            for delim in delimiters {
                if let r = newRemainder.range(of: delim, options: .caseInsensitive) {
                    corrPart = String(newRemainder[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    streamPart = String(newRemainder[r.lowerBound...])
                    break
                }
            }
            if streamPart.isEmpty {
                let newTokens = tokenizeText(newRemainder)
                let oldTokens = tokenizeText(oldRemainder)
                let corrCount = min(newTokens.count, max(1, oldTokens.count + 2))
                corrPart = newTokens[0..<corrCount].joined().trimmingCharacters(in: .whitespaces)
                streamPart = newTokens[corrCount...].joined()
            }

            currentState.confirmedText = prefix
            currentState.correctionOld = oldRemainder
            currentState.correctionNew = corrPart
            currentState.streamingText = streamPart

            // 0.5s smooth merge animation into confirmed text
            mergeTimer?.invalidate()
            mergeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if let new = self.currentState.correctionNew, !new.isEmpty {
                            if self.currentState.confirmedText.isEmpty {
                                self.currentState.confirmedText = new
                            } else if self.currentState.confirmedText.hasSuffix(" ") || new.hasPrefix(" ") {
                                self.currentState.confirmedText += new
                            } else {
                                self.currentState.confirmedText += " " + new
                            }
                        }
                        self.currentState.correctionOld = nil
                        self.currentState.correctionNew = nil
                    }
                    self.onUpdate?(self.currentState)
                }
            }
        } else {
            let tokens = tokenizeText(trimmed)
            let splitIdx = max(1, tokens.count - 2)
            currentState.confirmedText = tokens[0..<splitIdx].joined()
            currentState.streamingText = tokens[splitIdx...].joined()
        }

        return currentState
    }
}

// MARK: - Text Utilities

func tokenizeText(_ text: String) -> [String] {
    var tokens: [String] = []
    var currentWord = ""
    for char in text {
        if char.isWhitespace {
            if !currentWord.isEmpty {
                tokens.append(currentWord + " ")
                currentWord = ""
            }
        } else if char.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            if !currentWord.isEmpty {
                tokens.append(currentWord)
                currentWord = ""
            }
            tokens.append(String(char))
        } else {
            currentWord.append(char)
        }
    }
    if !currentWord.isEmpty {
        tokens.append(currentWord)
    }
    return tokens
}

func longestCommonPrefix(_ s1: String, _ s2: String) -> String {
    var prefix = ""
    var i1 = s1.startIndex
    var i2 = s2.startIndex
    while i1 < s1.endIndex && i2 < s2.endIndex && s1[i1] == s2[i2] {
        prefix.append(s1[i1])
        i1 = s1.index(after: i1)
        i2 = s2.index(after: i2)
    }
    return prefix
}

// MARK: - Multi-line Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 480
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Animation Model for Fly-in Micro-Interaction

@MainActor
final class OverlayAnimationModel: ObservableObject {
    @Published var flyOffset: CGSize = .zero
    @Published var flyScale: CGFloat = 1.0
    @Published var flyOpacity: Double = 1.0

    func reset() {
        flyOffset = .zero
        flyScale = 1.0
        flyOpacity = 1.0
    }
}

// MARK: - Overlay Window Controller

@MainActor
final class Overlay {
    private var panel: NSPanel?
    private let animModel = OverlayAnimationModel()
    private var presentationID = UUID()
    private var targetScreen: NSScreen?

    func show(state: AppState, screenPoint: CGPoint? = nil) {
        presentationID = UUID()
        if let screenPoint {
            targetScreen = NSScreen.screens.first { $0.frame.contains(screenPoint) }
                ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main
        }
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 236),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: OverlayView(state: state, animModel: animModel))
            self.panel = panel
        }
        reposition()
        animModel.reset()
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()
    }

    func reposition() {
        if let panel, let screen = targetScreen.flatMap({ target in NSScreen.screens.first { $0 == target } }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 24))
        }
    }

    func showStatus(state: AppState) {
        show(state: state)
        let id = presentationID
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.hide()
        }
    }

    func hide() {
        presentationID = UUID()
        animModel.reset()
        panel?.orderOut(nil)
    }

    /// Smoothly flies and shrinks the text card towards the target cursor screen position
    func flyAndDismiss(to targetPoint: CGPoint?, completion: @escaping () -> Void) {
        guard let panel, panel.isVisible else {
            completion()
            return
        }

        let panelFrame = panel.frame
        let panelCenter = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        let destination = targetPoint ?? CGPoint(x: panelCenter.x, y: panelCenter.y + 120)

        let dx = destination.x - panelCenter.x
        let dy = destination.y - panelCenter.y // Cocoa coordinates: positive is upward

        // SwiftUI coordinates: y increases downward, so vertical offset is -dy
        withAnimation(.easeInOut(duration: 0.25)) {
            self.animModel.flyScale = 0.08
            self.animModel.flyOffset = CGSize(width: dx, height: -dy)
            self.animModel.flyOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.animModel.reset()
            completion()
        }
    }
}

// MARK: - Breathing Cursor View

private struct BreathingCursorView: View {
    @State private var breathing = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 0.45, green: 0.92, blue: 1.0))
                .frame(width: 2.5, height: 22)
                .shadow(color: Color.cyan, radius: 5, x: 0, y: 0)
                .opacity(breathing ? 1.0 : 0.25)
                .animation(
                    Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: breathing
                )
        }
        .onAppear {
            breathing = true
        }
    }
}

// MARK: - Overlay Main View

private struct OverlayView: View {
    @ObservedObject var state: AppState
    @ObservedObject var animModel: OverlayAnimationModel

    var body: some View {
        VStack(spacing: 0) {
            // Upper Section: Text Preview Area (Three-State Visual Hierarchy)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    if !state.liveTranscriptState.isEmpty {
                        FlowLayout(spacing: 4, lineSpacing: 8) {
                            // 1. Confirmed Text: High-contrast pure white font
                            ForEach(Array(tokenizeText(state.liveTranscriptState.confirmedText).enumerated()), id: \.offset) { _, token in
                                Text(token)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            // 2. Live Inline Correction: Strikethrough old word + Cyan capsule new word
                            if let old = state.liveTranscriptState.correctionOld, !old.isEmpty {
                                Text(old)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .strikethrough(true, color: .white.opacity(0.65))
                                    .foregroundColor(.white.opacity(0.42))
                            }

                            if let new = state.liveTranscriptState.correctionNew, !new.isEmpty {
                                Text(new)
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.03, green: 0.10, blue: 0.16))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.20, green: 0.90, blue: 0.98),
                                                        Color(red: 0.10, green: 0.80, blue: 0.92)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .shadow(color: Color.cyan.opacity(0.75), radius: 8, x: 0, y: 0)
                                    )
                            }

                            // 3. Streaming Addition: Soft blue-cyan glowing gradient text
                            ForEach(Array(tokenizeText(state.liveTranscriptState.streamingText).enumerated()), id: \.offset) { _, token in
                                Text(token)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(red: 0.42, green: 0.82, blue: 1.0))
                                    .shadow(color: Color.cyan.opacity(0.55), radius: 6, x: 0, y: 0)
                            }

                            // Breathing cursor following the streaming tail
                            if state.recording {
                                BreathingCursorView()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // Empty / Listening placeholder state
                        HStack(spacing: 8) {
                            Text(state.recording ? state.label("Listening…", "正在听你说…") : state.status)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.65))

                            if state.recording {
                                BreathingCursorView()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }

                    // Cancel button in top-right
                    if state.recording {
                        Button {
                            state.cancel()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(state.label("Cancel", "取消"))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Divider: Subtle specular hairline
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 16)

            // Lower Section: Equalizer Waveforms + Center Microphone Badge
            HStack(spacing: 16) {
                // Left Spectrum Visualizer (16 bars)
                HStack(spacing: 3) {
                    ForEach(0..<16) { i in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.16, green: 0.85, blue: 0.98),
                                        Color(red: 0.62, green: 0.35, blue: 0.95)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 3.2, height: barHeight(index: i, isLeft: true))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Center Glowing Microphone Badge
                ZStack {
                    // Outer Ring with subtle cyan glow
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.cyan.opacity(0.85),
                                    Color.purple.opacity(0.5),
                                    Color.cyan.opacity(0.85)
                                ]),
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: Color.cyan.opacity(0.6), radius: 8, x: 0, y: 0)

                    // Inner circle
                    Circle()
                        .fill(Color(red: 0.06, green: 0.12, blue: 0.22).opacity(0.92))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
                        }

                    // App Mascot Color Icon
                    Image(nsImage: AppState.appMascotColorIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                .frame(width: 58, height: 58)

                // Right Spectrum Visualizer (16 bars)
                HStack(spacing: 3) {
                    ForEach(0..<16) { i in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.16, green: 0.85, blue: 0.98),
                                        Color(red: 0.62, green: 0.35, blue: 0.95)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 3.2, height: barHeight(index: i, isLeft: false))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
        }
        .frame(width: 520, height: 236)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.12, green: 0.30, blue: 0.43).opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.40), radius: 26, x: 0, y: 12)
        }
        // Micro-interaction: Fly and shrink into target document cursor
        .scaleEffect(animModel.flyScale)
        .offset(animModel.flyOffset)
        .opacity(animModel.flyOpacity)
    }

    private func barHeight(index: Int, isLeft: Bool) -> CGFloat {
        guard state.recording else { return 5 }
        let leftMultipliers: [CGFloat] = [0.25, 0.4, 0.6, 0.85, 1.15, 1.45, 1.7, 1.85, 1.6, 1.75, 1.35, 1.1, 0.85, 0.6, 0.45, 0.3]
        let rightMultipliers: [CGFloat] = [0.3, 0.45, 0.6, 0.85, 1.1, 1.35, 1.75, 1.6, 1.85, 1.7, 1.45, 1.15, 0.85, 0.6, 0.4, 0.25]
        let mult = isLeft ? leftMultipliers[index % 16] : rightMultipliers[index % 16]
        let base: CGFloat = 6
        let dynamic = CGFloat(min(state.level * 180, 1.0)) * 28 * mult
        return max(base, min(38, base + dynamic))
    }
}
