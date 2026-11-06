import AppKit
import ApplicationServices
import Carbon
import Foundation

public enum TargetAccessibility {
    private static let sensitiveKeywords: [String] = [
        "password", "passcode", "secret", "api key", "apikey", "token", "credit card", "cvv",
        "密码", "口令", "密钥", "令牌", "信用卡", "银行卡", "支付密码", "安全码"
    ]

    /// Wakes up Chromium / Electron accessibility tree if supported.
    public static func wakeManualAccessibility(processIdentifier: pid_t) {
        guard processIdentifier != 0 else { return }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let primary = AXUIElementSetAttributeValue(
            applicationElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        if primary == .attributeUnsupported {
            _ = AXUIElementSetAttributeValue(
                applicationElement,
                "AXEnhancedUserInterface" as CFString,
                kCFBooleanTrue
            )
        }
    }

    /// Captures the true focused application PID, app name, and AXUIElement.
    /// Always binds to the user-facing frontmost application to avoid getting trapped in child helper/renderers.
    public static func captureTargetFocus() -> (pid: pid_t, name: String, element: AXUIElement?) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return (0, "", nil)
        }
        let pid = frontmost.processIdentifier
        let name = frontmost.localizedName ?? ""
        wakeManualAccessibility(processIdentifier: pid)

        guard AXIsProcessTrusted() else {
            return (pid, name, nil)
        }

        return (pid, name, focusedElement(processIdentifier: pid))
    }

    /// Prefer the system-wide element when it agrees with the target application's
    /// focus. Some applications expose a helper-owned element through their AX tree.
    public static func focusedElement(processIdentifier pid: pid_t) -> AXUIElement? {
        guard pid != 0, AXIsProcessTrusted() else { return nil }
        wakeManualAccessibility(processIdentifier: pid)
        var appFocusedValue: CFTypeRef?
        let appElement = AXUIElementCreateApplication(pid)
        let appFocus: AXUIElement? = {
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &appFocusedValue) == .success,
                  let value = appFocusedValue, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }()

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success,
           let focused = focusedElementValue, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = (focused as! AXUIElement)
            var elementPID: pid_t = 0
            if AXUIElementGetPid(element, &elementPID) == .success && elementPID == pid {
                return element
            }
            if let appFocus, CFEqual(element, appFocus) { return element }
            return nil
        }
        return appFocus
    }

    /// Detects whether an element represents a sensitive / password field.
    public static func isSensitiveDestination(element: AXUIElement?) -> Bool {
        if IsSecureEventInputEnabled() { return true }
        guard let element else { return false }

        // Role & Subrole check
        var roleVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal) == .success,
           let role = roleVal as? String, role == "AXSecureTextField" {
            return true
        }
        var subroleVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleVal) == .success,
           let subrole = subroleVal as? String, subrole == "AXSecureTextField" {
            return true
        }

        // Protected content check
        var protectedVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXProtectedContent" as CFString, &protectedVal) == .success,
           let isProtected = protectedVal as? Bool, isProtected {
            return true
        }

        // Semantic metadata check (placeholder, title, description, help, identifier)
        let checkAttributes: [CFString] = [
            kAXPlaceholderValueAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXIdentifierAttribute as CFString
        ]
        for attr in checkAttributes {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr, &val) == .success,
               let text = val as? String {
                let lower = text.lowercased()
                if sensitiveKeywords.contains(where: { lower.contains($0) }) {
                    return true
                }
            }
        }

        return false
    }

    /// Waits until physical modifier keys (Shift, Ctrl, Alt, Fn) are released before posting ⌘V.
    public static func waitForModifiersReleased(timeout: TimeInterval = 0.2, completion: @escaping () -> Void) {
        let startTime = ProcessInfo.processInfo.systemUptime
        func check() {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let conflicting = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn])
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            if conflicting.isEmpty || elapsed >= timeout {
                completion()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    check()
                }
            }
        }
        check()
    }

    /// Posts a hardware-level Command+V sequence directly to .cghidEventTap.
    /// Emits the modifier flagsChanged transitions so Chromium / Electron apps (Antigravity, ChatGPT, Chrome)
    /// properly recognize the Command modifier, and posts to exactly ONE tap to prevent duplicated pastes.
    @discardableResult
    public static func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }

        // 1. Command Key Down (flagsChanged transition)
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true) else { return false }
        cmdDown.type = .flagsChanged
        cmdDown.flags = [.maskCommand, CGEventFlags(rawValue: 0x0008)]
        cmdDown.post(tap: .cghidEventTap)

        usleep(15_000) // 15ms

        // 2. 'V' Key Down (keyDown)
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) else { return false }
        vDown.flags = [.maskCommand, CGEventFlags(rawValue: 0x0008)]
        vDown.post(tap: .cghidEventTap)

        usleep(25_000) // 25ms

        // 3. 'V' Key Up (keyUp)
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        vUp.flags = [.maskCommand, CGEventFlags(rawValue: 0x0008)]
        vUp.post(tap: .cghidEventTap)

        usleep(15_000) // 15ms

        // 4. Command Key Up (flagsChanged transition)
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else { return false }
        cmdUp.type = .flagsChanged
        cmdUp.flags = []
        cmdUp.post(tap: .cghidEventTap)

        return true
    }
}
