// Draws Bento Stats' icon and mark: Resources/AppIcon.icns, and the one-colour glyph the
// settings window shows, Sources/AirStatUI/Resources/Logo.png.
//
// The icon is a graphite gauge: a gunmetal bezel round a black face, white ticks, and an
// orange needle and zone, under glass. Each size is drawn for its size, as Apple's own
// icons are, losing detail as it shrinks so what is left stays legible:
//
//   L    256 px and up   the whole object
//   M    128 px          no minor ticks or rim glint; bolder ticks and needle
//   S     64 px          one gradient bezel ring, a flat face, seven ticks, one soft shadow
//   XS    32 px          a grey circle with a gradient outline, four ticks, the needle
//   XXS   16 px          the circle, its outline and the needle
//
// usage, from the repository root: swift Scripts/make-icon.swift
import SwiftUI
import AppKit

enum Tier { case l, m, s, xs, xxs }

func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
          blue: Double(v & 0xff) / 255, opacity: a)
}

/// The dial's centre on the 1024 canvas: a little above the middle, for the shadow under it.
let center = CGPoint(x: 512, y: 500)
let orange = hex(0xff5a1f)
let gunmetal = LinearGradient(stops: [.init(color: hex(0xa2a4ab), location: 0), .init(color: hex(0x55575d), location: 0.3),
                                      .init(color: hex(0x1c1d20), location: 0.62), .init(color: hex(0x6a6c72), location: 1)],
                              startPoint: UnitPoint(x: 0.18, y: 0), endPoint: UnitPoint(x: 0.82, y: 1))
let capGrey = hex(0xcfd1d6)

/// Eleven majors over 270°, three minors between each pair; fewer for the small sizes.
let elevenTicks = (0..<11).map { -135 + 27 * Double($0) }
let minorTicks = (0..<41).filter { $0 % 4 != 0 }.map { -135 + 6.75 * Double($0) }
let sevenTicks = (0..<7).map { -135 + 45 * Double($0) }
/// The tick at 67.5° would sit under the needle (58°) and merge with it at 32 px.
let fourTicks: [Double] = [-135, -67.5, 0, 135]

/// `r` from `c` at `deg` degrees clockwise from straight up.
func polar(_ r: CGFloat, _ deg: Double, around c: CGPoint = center) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
}

/// Clockwise from `a0` to `a1` degrees, in one-degree steps.
func arc(_ r: CGFloat, _ a0: Double, _ a1: Double, around c: CGPoint = center) -> Path {
    let steps = max(2, Int(abs(a1 - a0)))
    return Path { $0.addLines((0...steps).map { polar(r, a0 + (a1 - a0) * Double($0) / Double(steps), around: c) }) }
}

func ticks(_ angles: [Double], outer: CGFloat, length: CGFloat) -> Path {
    Path { path in
        for deg in angles {
            path.move(to: polar(outer - length, deg))
            path.addLine(to: polar(outer, deg))
        }
    }
}

/// The needle, tapered from `base` at its tail to `tip`, round at both ends.
func needle(_ theta: Double, length: CGFloat, tail: CGFloat, base: CGFloat, tip: CGFloat) -> Path {
    let a = theta * .pi / 180
    let u = CGPoint(x: sin(a), y: -cos(a)), v = CGPoint(x: cos(a), y: sin(a))
    func pt(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
        CGPoint(x: center.x + along * u.x + across * v.x, y: center.y + along * u.y + across * v.y)
    }
    return Path { path in
        path.move(to: pt(-tail, base))
        path.addLine(to: pt(length, tip))
        for i in 1...24 {
            let t = Double(i) / 24 * .pi
            path.addLine(to: pt(length + tip * CGFloat(sin(t)), tip * CGFloat(cos(t))))
        }
        path.addLine(to: pt(-tail, -base))
        for i in 1...24 {
            let t = Double(i) / 24 * .pi
            path.addLine(to: pt(-tail - base * CGFloat(sin(t)), -base * CGFloat(cos(t))))
        }
        path.closeSubpath()
    }
}

/// Orange to dark orange across the needle itself, not across the canvas.
func needleGradient(_ path: Path) -> LinearGradient {
    let b = path.boundingRect
    return LinearGradient(colors: [hex(0xff8a4c), hex(0xd63d06)],
                          startPoint: UnitPoint(x: b.minX / 1024, y: b.minY / 1024),
                          endPoint: UnitPoint(x: b.maxX / 1024, y: b.maxY / 1024))
}

func disc<S: ShapeStyle>(_ r: CGFloat, _ fill: S, at c: CGPoint = center) -> some View {
    Circle().fill(fill).frame(width: 2 * r, height: 2 * r).position(c)
}

struct Icon: View {
    let tier: Tier

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [hex(0x2b2b30), hex(0x0d0d0f)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824).position(x: 512, y: 512)
            switch tier {
            case .l, .m: object(large: tier == .l)
            case .s: simplified
            case .xs, .xxs: outline(xs: tier == .xs)
            }
        }
        .frame(width: 1024, height: 1024)
    }

    /// 128 px and up: bezel and step, glass, shadows.
    @ViewBuilder
    private func object(large: Bool) -> some View {
        let cap: CGFloat = large ? 38 : 42
        let hand = needle(58, length: 210, tail: 54, base: large ? 14 : 19, tip: large ? 6.5 : 9.5)
        RoundedRectangle(cornerRadius: 183.5, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 3)
            .frame(width: 821, height: 821).position(x: 512, y: 512)
        disc(292, Color.black.opacity(0.6), at: CGPoint(x: 512, y: 534)).blur(radius: 26)
        disc(300, gunmetal)
        Circle().stroke(.white.opacity(0.75), lineWidth: large ? 3 : 4).frame(width: 597, height: 597).position(center)
        disc(266, LinearGradient(colors: [hex(0x050506), hex(0x45464b)], startPoint: .top, endPoint: .bottom))
        disc(252, RadialGradient(colors: [hex(0x1f2023), hex(0x050506)], center: UnitPoint(x: 0.5, y: 0.38),
                                 startRadius: 0, endRadius: 353))
        if large {
            ticks(minorTicks, outer: 232, length: 18)
                .stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        ticks(elevenTicks, outer: 232, length: large ? 46 : 54)
            .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: large ? 13 : 18, lineCap: .round))
        arc(243, 81, 135).stroke(orange, style: StrokeStyle(lineWidth: large ? 8 : 12, lineCap: .round))
        hand.fill(Color.black.opacity(0.55)).offset(x: 8, y: 12).blur(radius: large ? 6 : 8)
        hand.fill(needleGradient(hand))
        disc(cap + 1, Color.black.opacity(0.45), at: CGPoint(x: 515, y: 506)).blur(radius: large ? 6 : 8)
        disc(cap, RadialGradient(stops: [.init(color: hex(0xd9dbe0), location: 0), .init(color: hex(0x6c6e75), location: 0.5),
                                         .init(color: hex(0x26272b), location: 1)],
                                 center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 1.5 * cap))
        disc((cap / 4.5).rounded(), hex(0x2a2b2f))
        Ellipse().fill(LinearGradient(colors: [.white.opacity(large ? 0.2 : 0.14), .white.opacity(0)],
                                      startPoint: .top, endPoint: .bottom))
            .frame(width: 520, height: 300).rotationEffect(.degrees(-18)).position(x: 472, y: 350)
            .mask { disc(252, Color.white) }
        if large {
            arc(247, -72, -18).stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// 64 px: one gradient ring, a flat face, seven ticks, one soft shadow.
    @ViewBuilder
    private var simplified: some View {
        let hand = needle(58, length: 200, tail: 50, base: 27, tip: 14)
        disc(292, Color.black.opacity(0.5), at: CGPoint(x: 512, y: 530)).blur(radius: 20)
        disc(300, gunmetal)
        disc(258, hex(0x141416))
        ticks(sevenTicks, outer: 236, length: 62).stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        arc(246, 90, 135).stroke(orange, style: StrokeStyle(lineWidth: 18, lineCap: .round))
        hand.fill(needleGradient(hand))
        disc(48, capGrey)
    }

    /// 32 and 16 px: a grey circle with a gradient outline, and the needle.
    @ViewBuilder
    private func outline(xs: Bool) -> some View {
        let ring: CGFloat = xs ? 44 : 64
        let hand = xs ? needle(58, length: 196, tail: 44, base: 38, tip: 21) : needle(58, length: 196, tail: 40, base: 54, tip: 32)
        Circle().fill(hex(0x18181b)).frame(width: 600 - ring, height: 600 - ring).position(center)
        Circle().stroke(gunmetal, lineWidth: ring).frame(width: 600 - ring, height: 600 - ring).position(center)
        if xs {
            ticks(fourTicks, outer: 236, length: 74).stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 38, lineCap: .round))
        }
        hand.fill(needleGradient(hand))
        disc(xs ? 56 : 66, capGrey)
    }
}

/// The mark in black, the app tints it as a template: the dial's 270° sweep and the needle.
struct Glyph: View {
    var body: some View {
        let c = CGPoint(x: 512, y: 570)
        ZStack(alignment: .topLeading) {
            arc(404, -135, 135, around: c).stroke(.black, style: StrokeStyle(lineWidth: 96, lineCap: .round))
            Path { $0.move(to: c); $0.addLine(to: polar(300, 58, around: c)) }
                .stroke(.black, style: StrokeStyle(lineWidth: 110, lineCap: .round))
            disc(92, Color.black, at: c)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func write<V: View>(_ view: V, pixels: Int, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = CGFloat(pixels) / 1024
    guard let image = renderer.cgImage else { fatalError("render failed: \(url.lastPathComponent)") }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            let tier: Tier = pixels <= 16 ? .xxs : pixels <= 32 ? .xs : pixels <= 64 ? .s : pixels <= 128 ? .m : .l
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            write(Icon(tier: tier), pixels: pixels, to: iconset.appendingPathComponent(name))
        }
    }
    write(Glyph(), pixels: 1024, to: URL(fileURLWithPath: "Sources/AirStatUI/Resources/Logo.png"))
}
// Kept for checking each drawing by eye after a change.
if CommandLine.arguments.contains("--keep-iconset") {
    try? FileManager.default.removeItem(atPath: ".build/AppIcon.iconset")
    try! FileManager.default.copyItem(at: iconset, to: URL(fileURLWithPath: ".build/AppIcon.iconset"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", "Resources/AppIcon.icns", iconset.path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("Wrote Resources/AppIcon.icns and Sources/AirStatUI/Resources/Logo.png")
