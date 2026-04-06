import XCTest
@testable import Synapse

/// Tests the shell bootstrap line for the embedded terminal (cd + optional user on-boot command).
final class LocalTerminalBootCommandTests: XCTestCase {

    func test_initialSendLine_noCustomCommand_cdOnly() {
        let line = LocalTerminalBootCommand.initialSendLine(
            workingDirectory: "/tmp/myproject",
            onBootCommand: nil
        )
        XCTAssertEqual(line, "cd /tmp/myproject\n")
    }

    func test_initialSendLine_emptyStringCustomCommand_cdOnly() {
        let line = LocalTerminalBootCommand.initialSendLine(
            workingDirectory: "/tmp/myproject",
            onBootCommand: ""
        )
        XCTAssertEqual(line, "cd /tmp/myproject\n")
    }

    func test_initialSendLine_customCommand_chainsAfterCd() {
        let line = LocalTerminalBootCommand.initialSendLine(
            workingDirectory: "/tmp/myproject",
            onBootCommand: "git status"
        )
        XCTAssertEqual(line, "cd /tmp/myproject && git status\n")
    }

    func test_initialSendLine_escapesSpacesInPath() {
        let line = LocalTerminalBootCommand.initialSendLine(
            workingDirectory: "/Users/me/My Projects/vault",
            onBootCommand: nil
        )
        XCTAssertEqual(line, "cd /Users/me/My\\ Projects/vault\n")
    }

    func test_initialSendLine_customCommandWithSpacesInPath() {
        let line = LocalTerminalBootCommand.initialSendLine(
            workingDirectory: "/a/b c",
            onBootCommand: "echo hi"
        )
        XCTAssertEqual(line, "cd /a/b\\ c && echo hi\n")
    }
}
