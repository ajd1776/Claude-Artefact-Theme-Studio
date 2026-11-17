// Draws the 1024px app icon: a black terminal tile with a green prompt, on Apple's icon grid.
// Usage: swift make-icon.swift <output.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let green = NSColor(srgbRed: 0, green: 0.89, blue: 0.353, alpha: 1)      // --fg  #00e35a
let line = NSColor(srgbRed: 0.043, green: 0.353, blue: 0.169, alpha: 1)  // --line #0b5a2b
let blue = NSColor(srgbRed: 0.184, green: 0.337, blue: 1, alpha: 1)      // --blue-line #2f56ff

// macOS icon grid: 824pt tile, 100pt margin, continuous corners.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Box-drawn panel frame inside the tile.
let frame = NSBezierPath(rect: tile.insetBy(dx: 120, dy: 150))
frame.lineWidth = 10
line.setStroke()
frame.stroke()

// Title notch in the frame: a blue "selected tab" bar.
blue.setFill()
NSBezierPath(rect: NSRect(x: tile.minX + 170, y: tile.maxY - 162, width: 150, height: 24)).fill()

// The prompt.
let font = NSFont.monospacedSystemFont(ofSize: 330, weight: .bold)
let text = NSAttributedString(string: "›_", attributes: [.font: font, .foregroundColor: green, .kern: -10])
let ts = text.size()
text.draw(at: NSPoint(x: tile.midX - ts.width / 2, y: tile.midY - ts.height / 2 - 10))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
