import XCTest
import AppKit
import SwiftUI
@testable import Synapse

/// Tests for `Color(hex:)` and `NSColor(hexString:)` — theme import and folder palette depend on correct parsing.
final class HexColorParsingTests: XCTestCase {

    // MARK: - NSColor(hexString:)

    func test_nsColor_hexString_sixDigitRGB() {
        let color = NSColor(hexString: "#1F6FBF")!
        let rgb = color.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(rgb.redComponent, 31 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb.greenComponent, 111 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb.blueComponent, 191 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb.alphaComponent, 1.0, accuracy: 0.001)
    }

    func test_nsColor_hexString_eightDigitRGBA() {
        let color = NSColor(hexString: "#FF000080")!
        let rgb = color.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(rgb.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(rgb.blueComponent, 0, accuracy: 0.001)
        XCTAssertEqual(rgb.alphaComponent, 128 / 255.0, accuracy: 0.001)
    }

    func test_nsColor_hexString_trimsWhitespaceAndHashOptional() {
        let a = NSColor(hexString: "  #0F0F0F  ")!
        let b = NSColor(hexString: "0F0F0F")!
        XCTAssertEqual(a, b)
    }

    func test_nsColor_hexString_invalidLengthReturnsNil() {
        XCTAssertNil(NSColor(hexString: "#FFF"))
        XCTAssertNil(NSColor(hexString: "#GGGGGG"))
    }

    // MARK: - Color(hex:)

    func test_color_hex_wrapsNSColor() {
        let c = Color(hex: "#EBEBEB")!
        let ns = NSColor(c)
        let rgb = ns.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(rgb.redComponent, 235 / 255.0, accuracy: 0.02)
        XCTAssertEqual(rgb.greenComponent, 235 / 255.0, accuracy: 0.02)
        XCTAssertEqual(rgb.blueComponent, 235 / 255.0, accuracy: 0.02)
    }

    func test_color_hex_invalidReturnsNil() {
        XCTAssertNil(Color(hex: "not-a-color"))
    }
}
