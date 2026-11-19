import AppKit
import SwiftUI

@MainActor
final class VoiceBuddyAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: VoiceBuddyAppDelegate?

    let appState: AppState
    private var settingsWindowController: NSWindowController?
    private var isSettingsWindowOpen = false
    private var applicationShortcutMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var allowTermination = false
    /// Set by Sparkle immediately before it asks the host app to terminate for a relaunch.
    /// A menu-bar (LSUIElement) app otherwise vetoes that termination and "Install & Relaunch"
    /// silently stalls, because the normal quit path never runs.
    private var sparkleRelaunchPending = false

    /// - Parameters:
    ///   - skipModelPreload: Forwarded to `AppState` so unit tests can construct a
    ///     delegate without triggering MLX/Metal model preloading.
    ///   - skipMenuBar: Forwarded to `AppState` so unit tests do not register menu bar icons.
    init(
        skipModelPreload: Bool = AppState.isRunningUnitTests,
        skipMenuBar: Bool = AppState.isRunningUnitTests
    ) {
        let state = AppState(skipModelPreload: skipModelPreload, skipMenuBar: skipMenuBar)
        self.appState = state
        super.init()
        VoiceBuddyAppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.shared.record("app.delegate_did_finish_launching")
        configureApplicationMenu()
        installApplicationKeyboardShortcuts()
        appState.setupMenuBar()
        setupWorkspaceObservers()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allowed = allowTermination || sparkleRelaunchPending
        DiagnosticLog.shared.record("app.should_terminate allow=\(allowed) sparkle=\(sparkleRelaunchPending)")
        if allowed {
            return .terminateNow
        }
        closeKeyWindow()
        return .terminateCancel
    }

    /// Called by the updater right before Sparkle relaunches the app. Without marking the
    /// termination as allowed, `applicationShouldTerminate` would cancel Sparkle's quit request
    /// and the update would never install. Kept internal so it can be exercised in unit tests.
    func prepareForSparkleRelaunch() {
        DiagnosticLog.shared.record("app.sparkle_relaunch_pending")
        sparkleRelaunchPending = true
    }

    /// Resets the pending Sparkle relaunch flag if the update aborts before termination
    /// (e.g., user cancels admin authorization or installation fails), restoring normal veto behavior.
    func cancelSparkleRelaunch() {
        guard sparkleRelaunchPending else { return }
        DiagnosticLog.shared.record("app.sparkle_relaunch_cancelled")
        sparkleRelaunchPending = false
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Voice Buddy")
        let aboutItem = NSMenuItem(
            title: appState.t("About Voice Buddy…"),
            action: #selector(menuOpenAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: appState.t("Hide Voice Buddy"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: appState.t("Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: appState.t("Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: appState.t("Quit Voice Buddy"),
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: appState.t("File"))
        let closeItem = NSMenuItem(
            title: appState.t("Close Window"),
            action: #selector(closeKeyWindow),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = .command
        closeItem.target = self
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: appState.t("Edit"))
        editMenu.addItem(NSMenuItem(title: appState.t("Undo"), action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: appState.t("Redo"), action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: appState.t("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: appState.t("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: appState.t("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: appState.t("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: appState.t("Window"))
        let minItem = NSMenuItem(
            title: appState.t("Minimize"),
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(minItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func installApplicationKeyboardShortcuts() {
        applicationShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let chars = event.charactersIgnoringModifiers?.lowercased()

            let isCmd = (modifiers == .command)
            let isCtrlCmd = (modifiers == [.command, .control])

            if (isCmd && (chars == "q" || chars == "w" || event.keyCode == 12 || event.keyCode == 13)) ||
               (isCtrlCmd && (chars == "w" || event.keyCode == 13)) {
                DiagnosticLog.shared.record("shortcut.intercepted action=closeWindow chars=\(chars ?? "") keyCode=\(event.keyCode)")
                self?.closeKeyWindow()
                return nil
            }
            return event
        }
    }

    func showSettingsWindow(tab: AppTab? = nil, targetScreen: NSScreen? = nil) {
        if let tab { appState.selectedTab = tab }
        appState.refreshPermissions()

        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }
        guard let windowController = settingsWindowController,
              let window = windowController.window else { return }

        if window.isVisible || window.isMiniaturized {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            isSettingsWindowOpen = true
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let restored = window.setFrameUsingName("VoiceBuddySettings")
        let containingScreen = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })
        let minSafeSize = NSSize(width: 720, height: 560)
        let defaultSize = NSSize(width: 840, height: 600)

        if let screen = containingScreen, restored {
            let visibleFrame = screen.visibleFrame
            var frame = window.frame
            if frame.width < minSafeSize.width || frame.height < minSafeSize.height {
                frame.size = defaultSize
                frame.origin = NSPoint(
                    x: visibleFrame.midX - defaultSize.width / 2,
                    y: visibleFrame.midY - defaultSize.height / 2
                )
            }
            if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
            if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
            if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
            if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
            window.setFrame(frame, display: false)
        } else {
            let fallbackScreen = targetScreen
                ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main
            if let screen = fallbackScreen {
                let visibleFrame = screen.visibleFrame
                var frame = window.frame
                if frame.width < minSafeSize.width || frame.height < minSafeSize.height {
                    frame.size = defaultSize
                }
                frame.origin = NSPoint(
                    x: visibleFrame.midX - frame.width / 2,
                    y: visibleFrame.midY - frame.height / 2
                )
                if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
                if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
                if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
                if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
                window.setFrame(frame, display: false)
            }
        }

        isSettingsWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: MainView().environmentObject(appState)
        )
        let defaultSize = NSSize(width: 840, height: 600)
        let minSafeSize = NSSize(width: 720, height: 560)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Buddy"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = minSafeSize
        window.setFrameAutosaveName("VoiceBuddySettings")
        if !window.setFrameUsingName("VoiceBuddySettings") || window.frame.width < minSafeSize.width || window.frame.height < minSafeSize.height {
            var frame = window.frame
            frame.size = defaultSize
            window.setFrame(frame, display: false)
            window.center()
        }
        return NSWindowController(window: window)
    }

    @objc func closeKeyWindow() {
        if let keyWindow = NSApp.keyWindow {
            keyWindow.performClose(nil)
        } else if let window = settingsWindowController?.window, window.isVisible {
            window.performClose(nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        isSettingsWindowOpen = false
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindowController?.window else { return }
        isSettingsWindowOpen = false
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }

    @objc func menuOpenAbout() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        showSettingsWindow(tab: .about, targetScreen: targetScreen)
    }

    @objc func quit() {
        DiagnosticLog.shared.record("app.explicit_quit_requested")
        allowTermination = true
        NSApp.terminate(nil)
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let obs1 = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleSystemSettingsEvent(notification: notification)
            }
        }
        let obs2 = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleSystemSettingsEvent(notification: notification)
            }
        }
        let obs3 = center.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.allowTermination = true
            }
        }
        let obsSleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                DiagnosticLog.shared.record("system.will_sleep")
                self?.appState.cancel()
            }
        }
        let obsSessionResign = center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                DiagnosticLog.shared.record("system.session_resigned")
                self?.appState.cancel()
            }
        }
        let obsScreensSleep = center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                DiagnosticLog.shared.record("system.screens_sleep")
                self?.appState.cancel()
            }
        }
        workspaceObservers = [obs1, obs2, obs3, obsSleep, obsSessionResign, obsScreensSleep]
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    private func handleSystemSettingsEvent(notification: Notification) {
        guard appState.waitingForSystemSettingsReturn else { return }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bundleId = app.bundleIdentifier,
           bundleId.contains("systempreferences") || bundleId.contains("SystemSettings") {
            appState.waitingForSystemSettingsReturn = false
            appState.refreshPermissions()
            showSettingsWindow()
        }
    }
}

@main
enum VoiceBuddyApp {
    @MainActor
    static func main() {
        Bundle.installSwiftPMResourceBundleFallback()
        let application = NSApplication.shared
        let delegate = VoiceBuddyAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
