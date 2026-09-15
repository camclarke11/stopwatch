import AppKit

// Draws the app icon from the sitting cat sprite in pixel-cat.js, one crisp bitmap per iconset size.
let arguments = CommandLine.arguments
guard arguments.count == 3 else { print("usage: make-icon pixel-cat.js AppIcon.iconset"); exit(1) }
let source = try! String(contentsOfFile: arguments[1], encoding: .utf8)
let iconset = URL(fileURLWithPath: arguments[2])

func captures(_ pattern: String, in text: String) -> [[String]] {
    let regex = try! NSRegularExpression(pattern: pattern)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (1..<match.numberOfRanges).map { String(text[Range(match.range(at: $0), in: text)!]) }
    }
}
func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let value = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat(value >> 16 & 255) / 255, green: CGFloat(value >> 8 & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
}

let paletteLine = source.components(separatedBy: "\n").first { $0.contains("const palette") }!
var palette: [Character: CGColor] = [:]
for pair in captures("(\\w):'#([0-9a-f]{6})'", in: paletteLine) { palette[Character(pair[0])] = color(pair[1]) }
let sitStart = source.range(of: "sit: [")!.upperBound
let sitEnd = source.range(of: "]", range: sitStart..<source.endIndex)!.lowerBound
let rows = captures("'([^']*)'", in: String(source[sitStart..<sitEnd])).map { Array($0[0]) }
let pixels = rows.enumerated().flatMap { y, row in
    row.enumerated().compactMap { x, key in palette[key].map { (x: x, y: y, color: $0) } }
}
let minX = pixels.map(\.x).min()!, minY = pixels.map(\.y).min()!
let spriteWidth = pixels.map(\.x).max()! - minX + 1, spriteHeight = pixels.map(\.y).max()! - minY + 1

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: s); context.scaleBy(x: 1, y: -1)
    // Apple's macOS icon grid: an 824pt rounded square inside a 1024pt canvas.
    let inset = s * 100 / 1024
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = CGPath(roundedRect: plate, cornerWidth: plate.width * 0.225, cornerHeight: plate.width * 0.225, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025, color: color("000000", alpha: 0.28))
    context.addPath(shape); context.setFillColor(color("8db58a")); context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape); context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color("c3dcb6"), color("86ae84")] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])

    let fit = plate.width * 0.6 / CGFloat(max(spriteWidth, spriteHeight))
    let pixel = fit >= 1 ? fit.rounded(.down) : fit
    let width = CGFloat(spriteWidth) * pixel, height = CGFloat(spriteHeight) * pixel
    let left = ((s - width) / 2).rounded(), top = (plate.midY - height / 2 + plate.height * 0.02).rounded()
    context.setFillColor(color("2f4a31", alpha: 0.16))
    context.fillEllipse(in: CGRect(x: s / 2 - width * 0.42, y: top + height - pixel * 0.9, width: width * 0.84, height: pixel * 1.8))
    context.setShouldAntialias(false)
    for dot in pixels {
        context.setFillColor(dot.color)
        context.fill(CGRect(x: left + CGFloat(dot.x - minX) * pixel, y: top + CGFloat(dot.y - minY) * pixel, width: pixel, height: pixel))
    }
    context.restoreGState()
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try! render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
