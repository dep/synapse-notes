import XCTest
import AppKit
import SwiftUI
@testable import Synapse

/// Tests hex color parsing used by folder pastels and theme import (must reject garbage input).
final class ColorHexParsingTests: XCTestCase {

    func test_nsColor_hexString_sixDigitRGB() {
        let c = NSColor(hexString: "#FF8040")
        XCTAssertNotNil(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.001)
        XCTAssertEqual(g, 0.5, accuracy: 0.02)
        XCTAssertEqual(b, 0.25, accuracy: 0.02)
        XCTAssertEqual(a, 1.0, accuracy: 0.001)
    }

    func test_nsColor_hexString_eightDigitRGBA() {
        let c = NSColor(hexString: "#FF000080")
        XCTAssertNotNil(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.001)
        XCTAssertEqual(g, 0, accuracy: 0.001)
        XCTAssertEqual(b, 0, accuracy: 0.001)
        XCTAssertEqual(a, 128.0 / 255.0, accuracy: 0.02)
    }

    func test_nsColor_hexString_trimsWhitespaceAndHashOptional() {
        XCTAssertNotNil(NSColor(hexString: "  #00FF00  "))
        XCTAssertNotNil(NSColor(hexString: "0000FF"))
    }

    func test_nsColor_hexString_invalidLength_returnsNil() {
        XCTAssertNil(NSColor(hexString: "#FFF"))
        XCTAssertNil(NSColor(hexString: "#GGGGBB"))
    }

    func test_swiftUIColor_hex_usesNSColorBridge() {
        let color = Color(hex: "#F4ACAC")
        XCTAssertNotNil(color)
    }

    func test_swiftUIColor_hex_invalid_returnsNil() {
        XCTAssertNil(Color(hex: "nope"))
    }
}
