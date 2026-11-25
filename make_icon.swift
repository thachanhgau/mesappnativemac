// Vẽ logo 1024x1024 -> AppIcon.png. Chạy: swift make_icon.swift (build.sh tự gọi nếu chưa có AppIcon.icns)
import AppKit

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

// Nền bo góc theo lưới icon macOS (824px, lề 100px) + bóng đổ nhẹ
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(40, 120, 255), ending: rgb(140, 80, 240))!.draw(in: body, angle: -60)

// Bong bóng chat trắng có đuôi
let bubble = NSBezierPath(roundedRect: NSRect(x: 252, y: 370, width: 520, height: 340), xRadius: 170, yRadius: 170)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 330, y: 420))
tail.line(to: NSPoint(x: 280, y: 290))
tail.line(to: NSPoint(x: 460, y: 380))
tail.close()
NSColor.white.setFill()
bubble.fill()
tail.fill()

// Ba chấm "đang nhập"
for (i, x) in [392.0, 512.0, 632.0].enumerated() {
    rgb(60 + CGFloat(i) * 35, 110 - CGFloat(i) * 10, 250).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 38, y: 540 - 38, width: 76, height: 76)).fill()
}

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "AppIcon.png"))
