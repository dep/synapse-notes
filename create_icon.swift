#!/usr/bin/env swift
import Foundation
import CoreGraphics
import AppKit

let iconSize: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)

// Create NSImage with exact size
let image = NSImage(size: NSSize(width: iconSize, height: iconSize))

image.lockFocus()

// Draw background - dark gradient
let context = NSGraphicsContext.current?.cgContext

// Background gradient
let gradientColors = [
    NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0).cgColor,
    NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: gradientColors as CFArray,
                           locations: [0.0, 1.0])!

let center = CGPoint(x: iconSize/2, y: iconSize/2)
let radius = iconSize/2
context?.drawRadialGradient(gradient,
                           startCenter: center,
                           startRadius: 0,
                           endCenter: center,
                           endRadius: radius,
                           options: .drawsBeforeStartLocation)

// Draw white border
let borderPath = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: iconSize-80, height: iconSize-80), xRadius: 180, yRadius: 180)
NSColor.white.setStroke()
borderPath.lineWidth = 8
borderPath.stroke()

// Draw document icon in center
let docRect = NSRect(x: 312, y: 312, width: 400, height: 400)
let docImage = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)!
docImage.draw(in: docRect)

image.unlockFocus()

// Save as PNG
let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let pngData = bitmapRep.representation(using: .png, properties: [:])!

let fileURL = URL(fileURLWithPath: "/Users/dep/Sites/Synapse/Synapse/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
try! pngData.write(to: fileURL)

print("Created icon_512x512@2x.png")
