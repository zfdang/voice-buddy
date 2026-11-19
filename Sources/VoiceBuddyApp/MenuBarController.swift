import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private nonisolated(unsafe) var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
    }

    deinit {
        guard let item = statusItem else { return }
        statusItem = nil
        nonisolated(unsafe) let statusItemToRemove = item
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                NSStatusBar.system.removeStatusItem(statusItemToRemove)
            }
        } else {
            DispatchQueue.main.async {
                NSStatusBar.system.removeStatusItem(statusItemToRemove)
            }
        }
    }

    func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = AppMascotIcons.menuBarMascotIcon
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.toolTip = "Voice Buddy"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        rebuildMenu()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = (event?.type == .rightMouseUp) || (event?.modifierFlags.contains(.control) == true)
        if isRightClick {
            showStatusMenu()
        } else {
            showSettingsFromStatusItem()
        }
    }

    private func showStatusMenu() {
        guard let statusItem, let statusMenu else { return }
        rebuildMenu()
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showSettingsFromStatusItem() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        VoiceBuddyAppDelegate.shared?.showSettingsWindow(tab: nil, targetScreen: targetScreen)
    }

    func updateIcon(isRecording: Bool) {
        let icon = isRecording ? AppMascotIcons.menuBarActiveIcon : AppMascotIcons.menuBarMascotIcon
        icon.isTemplate = true
        statusItem?.button?.image = icon
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.imagePosition = .imageOnly
    }

    func rebuildMenu() {
        guard let appState else { return }
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(
            title: appState.t("Settings…"),
            action: #selector(menuOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let resultItem = NSMenuItem(
            title: appState.t("Recognition Result…"),
            action: #selector(menuOpenResult),
            keyEquivalent: ""
        )
        resultItem.target = self
        menu.addItem(resultItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: appState.t("About Voice Buddy…"),
            action: #selector(menuOpenAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updateItem = NSMenuItem(
            title: appState.t("Check for Updates…"),
            action: #selector(menuCheckUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: appState.t("Quit Voice Buddy"),
            action: #selector(menuQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusMenu = menu
    }

    @objc private func menuOpenSettings() {
        showSettingsFromStatusItem()
    }

    @objc private func menuOpenResult() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        VoiceBuddyAppDelegate.shared?.showSettingsWindow(tab: .recovery, targetScreen: targetScreen)
    }

    @objc private func menuOpenAbout() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        VoiceBuddyAppDelegate.shared?.showSettingsWindow(tab: .about, targetScreen: targetScreen)
    }

    @objc private func menuCheckUpdates() {
        appState?.checkForUpdates()
    }

    @objc private func menuQuit() {
        VoiceBuddyAppDelegate.shared?.quit()
    }
}
