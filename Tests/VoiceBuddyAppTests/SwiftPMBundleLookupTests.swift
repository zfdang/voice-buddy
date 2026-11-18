import XCTest
@testable import VoiceBuddyApp

final class SwiftPMBundleLookupTests: XCTestCase {
    func testRedirectsMissingAppRootBundleToContentsResources() {
        let mainURL = URL(fileURLWithPath: "/Applications/Voice Buddy.app")
        let resourceURL = URL(fileURLWithPath: "/Applications/Voice Buddy.app/Contents/Resources")
        let requested = "/Applications/Voice Buddy.app/KeyboardShortcuts_KeyboardShortcuts.bundle"
        let expected = "/Applications/Voice Buddy.app/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"

        let resolved = SwiftPMBundleLookup.fallbackPath(
            forRequestedPath: requested,
            mainBundleURL: mainURL,
            resourceURL: resourceURL,
            fileExists: { $0 == expected }
        )

        XCTAssertEqual(resolved, expected)
    }

    func testDoesNotRedirectWhenRequestedBundleAlreadyExistsAtRoot() {
        let mainURL = URL(fileURLWithPath: "/tmp/Build/Products")
        let resourceURL = URL(fileURLWithPath: "/tmp/Build/Products/Contents/Resources")
        let requested = "/tmp/Build/Products/KeyboardShortcuts_KeyboardShortcuts.bundle"

        let resolved = SwiftPMBundleLookup.fallbackPath(
            forRequestedPath: requested,
            mainBundleURL: mainURL,
            resourceURL: resourceURL,
            fileExists: { _ in true }
        )

        XCTAssertNil(resolved)
    }

    func testDoesNotRedirectNonBundleOrNestedOrExternalPaths() {
        let mainURL = URL(fileURLWithPath: "/Applications/Voice Buddy.app")
        let resourceURL = URL(fileURLWithPath: "/Applications/Voice Buddy.app/Contents/Resources")

        XCTAssertNil(
            SwiftPMBundleLookup.fallbackPath(
                forRequestedPath: "/Applications/Voice Buddy.app/Contents/Info.plist",
                mainBundleURL: mainURL,
                resourceURL: resourceURL,
                fileExists: { $0.contains("/Contents/Resources/") }
            )
        )
        XCTAssertNil(
            SwiftPMBundleLookup.fallbackPath(
                forRequestedPath: "/Applications/Voice Buddy.app/Contents/Subdir/Foo.bundle",
                mainBundleURL: mainURL,
                resourceURL: resourceURL,
                fileExists: { $0.contains("/Contents/Resources/") }
            )
        )
        XCTAssertNil(
            SwiftPMBundleLookup.fallbackPath(
                forRequestedPath: "/tmp/Other.bundle",
                mainBundleURL: mainURL,
                resourceURL: resourceURL,
                fileExists: { $0.contains("/Contents/Resources/") }
            )
        )
    }

    func testDoesNotRedirectWhenResourceBundleAlsoMissing() {
        let mainURL = URL(fileURLWithPath: "/Applications/Voice Buddy.app")
        let resourceURL = URL(fileURLWithPath: "/Applications/Voice Buddy.app/Contents/Resources")

        let resolved = SwiftPMBundleLookup.fallbackPath(
            forRequestedPath: "/Applications/Voice Buddy.app/Missing_Missing.bundle",
            mainBundleURL: mainURL,
            resourceURL: resourceURL,
            fileExists: { _ in false }
        )

        XCTAssertNil(resolved)
    }

    func testInstalledSwizzleSafelyHandlesMissingPathWithoutCrash() {
        Bundle.installSwiftPMResourceBundleFallback()
        XCTAssertNil(Bundle(path: "/nonexistent/KeyboardShortcuts_KeyboardShortcuts.bundle"))
    }
}
