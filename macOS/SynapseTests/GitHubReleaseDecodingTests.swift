import XCTest
@testable import Synapse

/// Tests for GitHubRelease and GitHubAsset JSON decoding.
///
/// AutoUpdater fetches the latest release from the GitHub API and decodes it
/// into these Codable structs.  If the decoder breaks (wrong key strategy,
/// missing fields, type mismatches) the update check silently fails.  These
/// tests pin the decoding contract against the real GitHub Releases API shape.
final class GitHubReleaseDecodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - GitHubRelease decoding

    func test_release_decodesTagName() throws {
        let json = """
        {
            "tag_name": "v2.1.0",
            "name": "Synapse 2.1.0",
            "assets": []
        }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v2.1.0")
    }

    func test_release_decodesName() throws {
        let json = """
        {
            "tag_name": "v1.0.0",
            "name": "Initial Release",
            "assets": []
        }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.name, "Initial Release")
    }

    func test_release_decodesEmptyAssetsArray() throws {
        let json = """
        {
            "tag_name": "v1.0.0",
            "name": "No Assets",
            "assets": []
        }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertTrue(release.assets.isEmpty)
    }

    func test_release_decodesAssetsArray() throws {
        let json = """
        {
            "tag_name": "v3.0.0",
            "name": "Release with Assets",
            "assets": [
                {
                    "name": "Synapse.dmg",
                    "browser_download_url": "https://github.com/dep/synapse/releases/download/v3.0.0/Synapse.dmg",
                    "size": 15728640
                }
            ]
        }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.assets.count, 1)
    }

    func test_release_tagNameWithVPrefixIsPreserved() throws {
        let json = """
        { "tag_name": "v1.2.3", "name": "Test", "assets": [] }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertTrue(release.tagName.hasPrefix("v"),
                      "v-prefix should be kept; AutoUpdater strips it explicitly")
    }

    func test_release_tagNameWithoutVPrefixDecodes() throws {
        let json = """
        { "tag_name": "1.2.3", "name": "Bare Version", "assets": [] }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "1.2.3")
    }

    // MARK: - GitHubAsset decoding

    func test_asset_decodesName() throws {
        let json = """
        {
            "name": "Synapse.dmg",
            "browser_download_url": "https://example.com/Synapse.dmg",
            "size": 8192
        }
        """.data(using: .utf8)!

        let asset = try decoder.decode(GitHubAsset.self, from: json)
        XCTAssertEqual(asset.name, "Synapse.dmg")
    }

    func test_asset_decodesBrowserDownloadUrl() throws {
        let expectedURL = "https://github.com/dep/synapse/releases/download/v1.0.0/Synapse.dmg"
        let json = """
        {
            "name": "Synapse.dmg",
            "browser_download_url": "\(expectedURL)",
            "size": 12345
        }
        """.data(using: .utf8)!

        let asset = try decoder.decode(GitHubAsset.self, from: json)
        XCTAssertEqual(asset.browserDownloadUrl, expectedURL,
                       "browser_download_url must decode via convertFromSnakeCase")
    }

    func test_asset_decodesSize() throws {
        let json = """
        {
            "name": "app.zip",
            "browser_download_url": "https://example.com/app.zip",
            "size": 99999999
        }
        """.data(using: .utf8)!

        let asset = try decoder.decode(GitHubAsset.self, from: json)
        XCTAssertEqual(asset.size, 99_999_999)
    }

    // MARK: - Multiple assets

    func test_release_decodesMultipleAssets() throws {
        let json = """
        {
            "tag_name": "v4.0.0",
            "name": "Multi-asset Release",
            "assets": [
                {
                    "name": "Synapse.dmg",
                    "browser_download_url": "https://example.com/Synapse.dmg",
                    "size": 10000000
                },
                {
                    "name": "Synapse.zip",
                    "browser_download_url": "https://example.com/Synapse.zip",
                    "size": 9000000
                }
            ]
        }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(release.assets[0].name, "Synapse.dmg")
        XCTAssertEqual(release.assets[1].name, "Synapse.zip")
    }

    // MARK: - Round-trip consistency

    func test_release_tagNameStrippedByAutoUpdater() throws {
        let json = """
        { "tag_name": "v2.5.0", "name": "Synapse 2.5", "assets": [] }
        """.data(using: .utf8)!

        let release = try decoder.decode(GitHubRelease.self, from: json)
        let stripped = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        XCTAssertEqual(stripped, "2.5.0",
                       "After stripping the v-prefix the version should be bare digits")
    }

    // MARK: - UpdateError enum

    func test_updateError_casesExist() {
        let errors: [UpdateError] = [.downloadFailed, .installFailed, .unsupportedFormat]
        XCTAssertEqual(errors.count, 3)
    }

    func test_updateError_isError() {
        let e: Error = UpdateError.downloadFailed
        XCTAssertNotNil(e)
    }
}
