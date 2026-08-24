import AppKit

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 228, yRadius: 228).fill()

NSColor(calibratedRed: 0.78, green: 0.14, blue: 0.18, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840), xRadius: 196, yRadius: 196).fill()

let text = "VP" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 390, weight: .bold),
    .foregroundColor: NSColor.white
]
let textSize = text.size(withAttributes: attrs)
text.draw(
    at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 - 18),
    withAttributes: attrs
)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("failed to encode icon\n", stderr)
    exit(1)
}
try png.write(to: outURL)
