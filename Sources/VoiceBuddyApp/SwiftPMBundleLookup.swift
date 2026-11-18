import Foundation
import ObjectiveC.runtime

/// Resolves SwiftPM `Bundle.module` lookups inside packaged macOS `.app` bundles.
///
/// SwiftPM's generated `resource_bundle_accessor.swift` searches
/// `Bundle.main.bundleURL.appendingPathComponent("<Target>.bundle")` (which points
/// to `<App>.app/<Target>.bundle` at the bundle root, where codesign forbids
/// unsealed directories) and then falls back to the compile-time build path.
/// Because `scripts/build.sh` places resource bundles inside `Contents/Resources/`,
/// packaged CI builds crash with `Swift.fatalError` whenever any dependency
/// accesses `Bundle.module` (e.g., `KeyboardShortcuts`, `Hub`, `LaunchAtLogin`).
enum SwiftPMBundleLookup {
    static func fallbackPath(
        forRequestedPath requestedPath: String,
        mainBundleURL: URL,
        resourceURL: URL?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        guard let resourceURL else { return nil }

        let requestedURL = URL(fileURLWithPath: requestedPath).standardizedFileURL
        let bundleName = requestedURL.lastPathComponent
        guard bundleName.hasSuffix(".bundle"), !bundleName.isEmpty else {
            return nil
        }

        let expectedRootPath = mainBundleURL.standardizedFileURL
            .appendingPathComponent(bundleName)
            .path
        guard requestedURL.path == expectedRootPath else {
            return nil
        }

        guard !fileExists(requestedURL.path) else {
            return nil
        }

        let candidatePath = resourceURL.standardizedFileURL
            .appendingPathComponent(bundleName)
            .path
        guard candidatePath != requestedURL.path, fileExists(candidatePath) else {
            return nil
        }

        return candidatePath
    }
}

extension Bundle {
    private static let installSwiftPMResourceBundleFallbackOnce: Void = {
        // Warm Bundle.main URLs before exchanging implementations.
        _ = Bundle.main.bundleURL
        _ = Bundle.main.resourceURL

        let originalSelector = NSSelectorFromString("initWithPath:")
        let swizzledSelector = #selector(Bundle.vb_swiftPMInitWithPath(_:))
        guard let originalMethod = class_getInstanceMethod(Bundle.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzledSelector)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    /// Installs an idempotent `-[NSBundle initWithPath:]` fallback that redirects
    /// missing `<App>.app/<Name>.bundle` lookups to `<App>.app/Contents/Resources/<Name>.bundle`.
    static func installSwiftPMResourceBundleFallback() {
        _ = installSwiftPMResourceBundleFallbackOnce
    }

    @objc private func vb_swiftPMInitWithPath(_ path: String) -> Bundle? {
        let resolvedPath = SwiftPMBundleLookup.fallbackPath(
            forRequestedPath: path,
            mainBundleURL: Bundle.main.bundleURL,
            resourceURL: Bundle.main.resourceURL
        ) ?? path
        return vb_swiftPMInitWithPath(resolvedPath)
    }
}
