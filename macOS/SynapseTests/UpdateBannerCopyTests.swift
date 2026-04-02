import XCTest
@testable import Synapse

/// Tests user-visible update banner strings (auto-update UX).
final class UpdateBannerCopyTests: XCTestCase {

    func test_icon_restartUsesCheckmark() {
        XCTAssertEqual(
            UpdateBannerCopy.iconName(downloadProgress: nil, restartRequired: true),
            "checkmark.circle.fill"
        )
    }

    func test_icon_downloadingUsesArrow() {
        XCTAssertEqual(
            UpdateBannerCopy.iconName(downloadProgress: 0.5, restartRequired: false),
            "arrow.down.circle.fill"
        )
    }

    func test_title_updateAvailable() {
        XCTAssertEqual(
            UpdateBannerCopy.title(version: "2.0.0", downloadProgress: nil, restartRequired: false),
            "Update available: v2.0.0"
        )
    }

    func test_title_downloadingIncludesPercent() {
        XCTAssertEqual(
            UpdateBannerCopy.title(version: "2.0.0", downloadProgress: 0.42, restartRequired: false),
            "Downloading v2.0.0… 42%"
        )
    }

    func test_title_installed() {
        XCTAssertEqual(
            UpdateBannerCopy.title(version: "2.0.0", downloadProgress: nil, restartRequired: true),
            "Synapse v2.0.0 installed"
        )
    }

    func test_subtitle_installPrompt() {
        XCTAssertEqual(
            UpdateBannerCopy.subtitle(downloadProgress: nil, restartRequired: false),
            "Click Install to update automatically"
        )
    }

    func test_subtitle_restartPrompt() {
        XCTAssertEqual(
            UpdateBannerCopy.subtitle(downloadProgress: nil, restartRequired: true),
            "Restart to finish updating"
        )
    }
}
