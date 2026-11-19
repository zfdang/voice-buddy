import Foundation
import XCTest
@testable import VoiceBuddyApp
@testable import VoiceBuddyCore

@MainActor
final class StoreArchitectureTests: XCTestCase {
    func testPreferencesStorePersistsAndNotifiesCallbacks() {
        let suiteName = "VoiceBuddy.PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(defaults: defaults, defaultsKey: "prefs")
        var observedRefinementChanges: [(Refinement, Refinement)] = []
        store.onPreferencesChanged = { old, new in
            if old.refinement != new.refinement {
                observedRefinementChanges.append((old.refinement, new.refinement))
            }
        }

        store.preferences.refinement = .balanced
        store.preferences.interfaceLanguage = "zh"

        XCTAssertEqual(observedRefinementChanges.count, 1)
        XCTAssertEqual(observedRefinementChanges.first?.0, .light)
        XCTAssertEqual(observedRefinementChanges.first?.1, .balanced)

        let reloaded = PreferencesStore(defaults: defaults, defaultsKey: "prefs")
        XCTAssertEqual(reloaded.preferences.refinement, .balanced)
        XCTAssertEqual(reloaded.preferences.interfaceLanguage, "zh")
    }

    func testAppLocalizerResolvesEnglishAndChineseFromXCStrings() {
        XCTAssertGreaterThanOrEqual(AppLocalizer.catalogCountForTesting, 240)

        XCTAssertEqual(AppLocalizer.string("General", interfaceLanguage: "en"), "General")
        XCTAssertEqual(AppLocalizer.string("General", interfaceLanguage: "zh"), "通用")

        XCTAssertEqual(AppLocalizer.string("Check for Updates…", interfaceLanguage: "en"), "Check for Updates…")
        XCTAssertEqual(AppLocalizer.string("Check for Updates…", interfaceLanguage: "zh"), "检查更新…")

        let formattedEn = AppLocalizer.formatted("View Developer Context (%d terms)", interfaceLanguage: "en", 42)
        let formattedZh = AppLocalizer.formatted("View Developer Context (%d terms)", interfaceLanguage: "zh", 42)
        XCTAssertEqual(formattedEn, "View Developer Context (42 terms)")
        XCTAssertEqual(formattedZh, "查看传入模型的开发词汇表（42 个）")
    }

    func testLiveHUDStateNotifiesRecordingChanges() {
        let hud = LiveHUDState()
        var recordedEvents: [Bool] = []
        hud.onRecordingChanged = { recordedEvents.append($0) }

        hud.recording = true
        hud.recording = true // duplicate value should not re-emit
        hud.level = 0.42
        hud.liveTranscript = "hello"
        hud.recording = false

        XCTAssertEqual(recordedEvents, [true, false])
        XCTAssertEqual(hud.level, 0.42)
        XCTAssertEqual(hud.liveTranscript, "hello")
    }

    func testModelCatalogStoreCacheAndSelectionIsolation() async throws {
        let suiteName = "VoiceBuddy.ModelCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("vb-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let prefsStore = PreferencesStore(defaults: defaults, defaultsKey: "prefs")
        let hud = LiveHUDState()
        var busy = false
        var result = ""
        let catalog = ModelCatalogStore(
            models: LocalModels(root: tempRoot),
            preferencesStore: prefsStore,
            hud: hud,
            isBusy: { busy },
            setBusy: { busy = $0 },
            getOriginal: { "原始文本" },
            setResult: { result = $0 }
        )

        let expectCheck = expectation(description: "checkModelCacheStatus")
        catalog.checkModelCacheStatus {
            expectCheck.fulfill()
        }
        await fulfillment(of: [expectCheck], timeout: 5.0)

        XCTAssertTrue(catalog.cachedSpeechModelIDs.contains("apple-speech"))
        XCTAssertFalse(catalog.isSpeechDownloaded, "Default qwen-asr-0.6b is not cached in empty tempRoot")
        XCTAssertFalse(catalog.isEditorDownloaded)

        await catalog.testRefinement(mode: .original)
        XCTAssertEqual(result, "原始文本")
    }

    func testCancelDownloadLocalizationKeyResolvesInBothLanguages() {
        XCTAssertEqual(AppLocalizer.string("Cancel Download", interfaceLanguage: "en"), "Cancel Download")
        XCTAssertEqual(AppLocalizer.string("Cancel Download", interfaceLanguage: "zh"), "取消下载")
    }

    func testShortcutModeSwitchingTogglesFnMonitors() {
        let suiteName = "VoiceBuddy.ShortcutModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(defaults: defaults, defaultsKey: "prefs")
        XCTAssertFalse(state.preferences.useFnKey)
        XCTAssertFalse(state.dictation.activeShortcutUsesFnForTesting)
        XCTAssertFalse(state.dictation.isFnMonitorActiveForTesting)

        state.preferences.useFnKey = true
        XCTAssertTrue(state.dictation.activeShortcutUsesFnForTesting)
        XCTAssertTrue(state.dictation.isFnMonitorActiveForTesting, "Enabling Fn key mode must install Fn event monitors")

        state.preferences.useFnKey = false
        XCTAssertFalse(state.dictation.activeShortcutUsesFnForTesting)
        XCTAssertFalse(state.dictation.isFnMonitorActiveForTesting, "Disabling Fn key mode must tear down Fn event monitors")
    }

    func testMenuBarControllerBuildsLocalizedMenuItemsWithoutStatusItem() throws {
        let suiteName = "VoiceBuddy.MenuBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(defaults: defaults, defaultsKey: "prefs")
        state.preferences.interfaceLanguage = "en"
        let controller = MenuBarController(appState: state, registerStatusItem: false)

        let enMenu = try XCTUnwrap(controller.buildMenu())
        let enTitles = enMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(enTitles, [
            "Settings…",
            "Recognition Result…",
            "About Voice Buddy…",
            "Check for Updates…",
            "Quit Voice Buddy"
        ])

        state.preferences.interfaceLanguage = "zh"
        let zhMenu = try XCTUnwrap(controller.buildMenu())
        let zhTitles = zhMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(zhTitles, [
            "设置…",
            "识别结果…",
            "关于 Voice Buddy…",
            "检查更新…",
            "退出 Voice Buddy"
        ])
    }
}
