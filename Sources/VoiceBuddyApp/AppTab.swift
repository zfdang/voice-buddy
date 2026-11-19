import AppKit
import Foundation

public enum AppTab: Int, CaseIterable, Identifiable {
    case general = 0
    case permissions = 1
    case speech = 2
    case editor = 3
    case recovery = 4
    case about = 5
    public var id: Int { rawValue }

    public static let sidebarGroups: [[AppTab]] = [
        [.general, .permissions, .speech, .editor],
        [.recovery],
        [.about]
    ]
}

@MainActor
enum AppMascotIcons {
    static let menuBarMascotIcon: NSImage = {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)

        let url1x = Bundle.main.url(forResource: "MenuBarIconTemplate", withExtension: "png")
            ?? Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
        let url2x = Bundle.main.url(forResource: "MenuBarIconTemplate@2x", withExtension: "png")
            ?? Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png")

        if let url1x, let data1x = try? Data(contentsOf: url1x), let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = size
            img.addRepresentation(rep1x)
        }
        if let url2x, let data2x = try? Data(contentsOf: url2x), let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = size
            img.addRepresentation(rep2x)
        }

        if !img.representations.isEmpty {
            img.isTemplate = true
            return img
        }

        if let url = url1x ?? url2x, let raw = NSImage(contentsOf: url) {
            raw.size = size
            raw.isTemplate = true
            return raw
        }

        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Buddy") ?? NSImage()
        fallback.size = size
        fallback.isTemplate = true
        return fallback
    }()

    static let menuBarActiveIcon: NSImage = {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)

        let url1x = Bundle.main.url(forResource: "MenuBarIconActiveTemplate", withExtension: "png")
            ?? Bundle.main.url(forResource: "MenuBarIconColor", withExtension: "png")
        let url2x = Bundle.main.url(forResource: "MenuBarIconActiveTemplate@2x", withExtension: "png")
            ?? Bundle.main.url(forResource: "MenuBarIconColor@2x", withExtension: "png")

        if let url1x, let data1x = try? Data(contentsOf: url1x), let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = size
            img.addRepresentation(rep1x)
        }
        if let url2x, let data2x = try? Data(contentsOf: url2x), let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = size
            img.addRepresentation(rep2x)
        }

        if !img.representations.isEmpty {
            img.isTemplate = true
            return img
        }

        if let url = url1x ?? url2x, let raw = NSImage(contentsOf: url) {
            raw.size = size
            raw.isTemplate = true
            return raw
        }

        let fallback = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording")
            ?? NSImage()
        fallback.size = size
        fallback.isTemplate = true
        return fallback
    }()

    static let appMascotColorIcon: NSImage = {
        let size = NSSize(width: 44, height: 44)
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = size
            img.isTemplate = false
            return img
        }

        let url1x = Bundle.main.url(forResource: "MenuBarIconColor", withExtension: "png")
        let url2x = Bundle.main.url(forResource: "MenuBarIconColor@2x", withExtension: "png")

        let img = NSImage(size: size)
        if let url2x, let data2x = try? Data(contentsOf: url2x), let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = size
            img.addRepresentation(rep2x)
        } else if let url1x, let data1x = try? Data(contentsOf: url1x), let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = size
            img.addRepresentation(rep1x)
        }

        if !img.representations.isEmpty {
            img.isTemplate = false
            return img
        }

        return menuBarActiveIcon
    }()
}
