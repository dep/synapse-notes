import Cocoa

let iconSize: CGFloat = 1024
let image = NSImage(size: NSSize(width: iconSize, height: iconSize))

image.lockFocus()

// Draw gradient background
let context = NSGraphicsContext.current!.cgContext

let colors = [
    NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0).cgColor,
    NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: colors as CFArray,
                           locations: [0.0, 1.0])!

context.drawRadialGradient(gradient,
                           startCenter: CGPoint(x: iconSize/2, y: iconSize/2),
                           startRadius: 0,
                           endCenter: CGPoint(x: iconSize/2, y: iconSize/2),
                           endRadius: iconSize/2,
                           options: .drawsBeforeStartLocation)

// Draw rounded rect background
let roundedRect = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: iconSize-80, height: iconSize-80), xRadius: 180, yRadius: 180)
NSColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1.0).setFill()
roundedRect.fill()

// Draw white border
NSColor(white: 1.0, alpha: 0.2).setStroke()
roundedRect.lineWidth = 6
roundedRect.stroke()

// Draw document icon
if let docImage = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil) {
    let docRect = NSRect(x: 312, y: 312, width: 400, height: 400)
    NSColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1.0).setFill()
    docImage.draw(in: docRect)
}

image.unlockFocus()

// Save to file
if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {

    let path = "/Users/dep/Sites/Synapse/Synapse/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
    try? pngData.write(to: URL(fileURLWithPath: path))
    print("Created icon at \(path)")
}
