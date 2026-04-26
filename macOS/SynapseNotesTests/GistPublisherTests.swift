import XCTest
@testable import Synapse

/// Tests for GistPublisher: publishing notes to GitHub Gists
final class GistPublisherTests: XCTestCase {
    var sut: GistPublisher!

    override func setUp() {
        super.setUp()
        sut = GistPublisher()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func test_init_startsInIdleState() {
        XCTAssertEqual(sut.state, .idle, "Publisher should start in idle state")
    }

    // MARK: - State Transitions

    func test_publish_startsWithPublishingState() {
        let expectation = self.expectation(description: "State changes to publishing")
        var stateHistory: [GistPublisher.PublishState] = []

        let cancellable = sut.$state.sink { state in
            stateHistory.append(state)
            if state == .publishing {
                expectation.fulfill()
            }
        }

        // Trigger publish (will fail due to no token, but should start with publishing state)
        let note = NoteContent(filename: "test.md", content: "# Test")
        sut.publish(note, pat: "test-token")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(stateHistory.contains(.publishing), "Should transition to publishing state")
        cancellable.cancel()
    }

    // MARK: - Input Validation

    func test_publish_withoutPAT_returnsError() {
        let expectation = self.expectation(description: "Returns error for missing PAT")
        let note = NoteContent(filename: "test.md", content: "# Test")

        var receivedError = false
        let cancellable = sut.$state.sink { state in
            if case .failed(let error) = state {
                if !receivedError {
                    receivedError = true
                    XCTAssertTrue(error.contains("token") || error.contains("PAT") || error.contains("required"), "Error should mention missing token: got '\(error)'")
                    expectation.fulfill()
                }
            }
        }

        sut.publish(note, pat: "")

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func test_publish_withWhitespaceOnlyPAT_returnsError() {
        let expectation = self.expectation(description: "Returns error for whitespace-only PAT")
        let note = NoteContent(filename: "test.md", content: "# Test")

        var receivedError = false
        let cancellable = sut.$state.sink { state in
            if case .failed(let error) = state {
                if !receivedError {
                    receivedError = true
                    XCTAssertTrue(error.contains("token") || error.contains("PAT") || error.contains("required"), "Error should mention missing token: got '\(error)'")
                    expectation.fulfill()
                }
            }
        }

        sut.publish(note, pat: "   ")

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    // MARK: - Note Content Validation

    func test_publish_withEmptyContent_returnsError() {
        let expectation = self.expectation(description: "Returns error for empty content")
        let note = NoteContent(filename: "test.md", content: "")

        var receivedError = false
        let cancellable = sut.$state.sink { state in
            if case .failed(let error) = state {
                if !receivedError {
                    receivedError = true
                    XCTAssertTrue(error.contains("content") || error.contains("empty") || error.contains("Content"), "Error should mention empty content: got '\(error)'")
                    expectation.fulfill()
                }
            }
        }

        sut.publish(note, pat: "ghp_validtoken")

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func test_publish_withEmptyFilename_returnsError() {
        let expectation = self.expectation(description: "Returns error for empty filename")
        let note = NoteContent(filename: "", content: "# Test")

        var receivedError = false
        let cancellable = sut.$state.sink { state in
            if case .failed(let error) = state {
                if !receivedError {
                    receivedError = true
                    XCTAssertTrue(error.contains("filename") || error.contains("Filename") || error.contains("name"), "Error should mention filename: got '\(error)'")
                    expectation.fulfill()
                }
            }
        }

        sut.publish(note, pat: "ghp_validtoken")

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    // MARK: - Reset State

    func test_reset_returnsToIdleState() {
        let note = NoteContent(filename: "test.md", content: "# Test")
        sut.publish(note, pat: "ghp_test")

        // Wait a bit for the async operation
        let expectation = self.expectation(description: "Reset returns to idle")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sut.reset()
            XCTAssertEqual(self.sut.state, .idle, "Reset should return to idle state")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - NoteContent Struct

    func test_noteContent_storesFilename() {
        let note = NoteContent(filename: "my-note.md", content: "Hello")
        XCTAssertEqual(note.filename, "my-note.md")
    }

    func test_noteContent_storesContent() {
        let note = NoteContent(filename: "test.md", content: "# Hello World")
        XCTAssertEqual(note.content, "# Hello World")
    }
}
