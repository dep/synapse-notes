import XCTest
@testable import Synapse

/// Unit tests for `AppState.mergedGitDateCache` — when a refresh returns empty (timeout / git
/// failure) we must not wipe a previously good cache, or the UI reverts to wrong filesystem dates.
final class AppStateGitDateCacheMergeTests: XCTestCase {

    func test_mergedGitDateCache_freshBuild_emptyRefresh_keepsEmpty() {
        let merged = AppState.mergedGitDateCache(previous: [:], fromRefresh: [:])
        XCTAssertTrue(merged.isEmpty)
    }

    func test_mergedGitDateCache_successfulRefresh_replaces() {
        let u = URL(fileURLWithPath: "/vault/a.md").standardizedFileURL
        let d = Date(timeIntervalSince1970: 1_000)
        let previous: [URL: GitService.FileDates] = [u: GitService.FileDates(created: d, updated: d)]
        let incoming: [URL: GitService.FileDates] = [
            u: GitService.FileDates(created: d, updated: Date(timeIntervalSince1970: 2_000))
        ]
        let merged = AppState.mergedGitDateCache(previous: previous, fromRefresh: incoming)
        XCTAssertEqual(merged[u]?.updated, Date(timeIntervalSince1970: 2_000))
    }

    func test_mergedGitDateCache_emptyRefresh_preservesNonEmptyPrevious() {
        let u = URL(fileURLWithPath: "/vault/note.md").standardizedFileURL
        let d = Date(timeIntervalSince1970: 42)
        let previous: [URL: GitService.FileDates] = [u: GitService.FileDates(created: d, updated: d)]
        let merged = AppState.mergedGitDateCache(previous: previous, fromRefresh: [:])
        XCTAssertEqual(merged[u]?.created, d)
        XCTAssertEqual(merged.count, 1)
    }
}
