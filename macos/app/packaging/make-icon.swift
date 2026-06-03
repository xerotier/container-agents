// SPDX-License-Identifier: MIT
// Rasterize the Xerotier favicon SVG to a crisp square PNG at the requested
// size. Vector source → sharp at any icon size, with no external rasterizer
// (works headless / in CI). Usage: make-icon <src.svg> <out.png> [pixels]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-icon <src.svg> <out.png> [px]\n".utf8)); exit(2)
}
let src = args[1]
let out = args[2]
let px = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024

guard let image = NSImage(contentsOfFile: src) else {
    FileHandle.standardError.write(Data("could not load \(src)\n".utf8)); exit(1)
}

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    FileHandle.standardError.write(Data("failed to allocate bitmap\n".utf8)); exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
           from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode png\n".utf8)); exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out) (\(px)px)")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1)
}
