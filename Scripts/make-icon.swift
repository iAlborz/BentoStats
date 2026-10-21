// Draws Bento Stats' icon and mark: Resources/AppIcon.icns, and the one-colour glyph the
// settings window shows, Sources/AirStatUI/Resources/Logo.png.
//
// The icon is a black lacquer bento box: a gold rim, and three compartments in the
// panel's colours with a ring, bars and a line in them. Every corner is concentric:
// each radius is the body's 185 less how far that layer sits in from its edge. Smaller
// sizes drop detail: at 64 pixels one bar and no ring track, at 32 and below the
// compartments alone.
//
// usage, from the repository root: swift Scripts/make-icon.swift
import SwiftUI
import AppKit

enum Detail { case full, small, tiny }

func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
          blue: Double(v & 0xff) / 255, opacity: a)
}

func diagonal(_ a: UInt32, _ b: UInt32) -> LinearGradient {
    LinearGradient(colors: [hex(a), hex(b)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A rounded rectangle at its place on the 1024 canvas.
func box<S: ShapeStyle>(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: S) -> some View {
    RoundedRectangle(cornerRadius: r, style: .continuous).fill(fill)
        .frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
}

/// A ring of `inset` from the body's edge, its corner the body's 185 less that inset.
func rim(_ inset: CGFloat, _ color: Color, _ width: CGFloat) -> some View {
    let size = 824 - 2 * inset
    return RoundedRectangle(cornerRadius: 185 - inset, style: .continuous)
        .stroke(color, lineWidth: width)
        .frame(width: size, height: size).position(x: 512, y: 512)
}

struct Icon: View {
    let detail: Detail

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [hex(0x3a3a3f), hex(0x141416)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824).position(x: 512, y: 512)
                .shadow(color: .black.opacity(detail == .tiny ? 0 : 0.3), radius: 12, y: 10)
            if detail == .full { rim(2, .white.opacity(0.12), 4) }
            if detail != .tiny { rim(46, hex(0xf2c46b, 0.6), detail == .full ? 6 : 10) }
            box(205, 205, 388, 388, 80, diagonal(0x0a84ff, 0x5ac8fa))
            box(619, 205, 200, 614, 80, diagonal(0xff9f0a, 0xffd60a))
            box(205, 619, 388, 200, 80, diagonal(0xbf5af2, 0xff375f))
            if detail != .tiny { glyphs }
        }
        .frame(width: 1024, height: 1024)
    }

    @ViewBuilder
    private var glyphs: some View {
        let ring = detail == .full ? 38.0 : 54.0
        if detail == .full {
            Circle().stroke(.white.opacity(0.35), lineWidth: ring)
                .frame(width: 220, height: 220).position(x: 399, y: 399)
        }
        Circle().trim(from: 0, to: 0.75)
            .stroke(.white, style: StrokeStyle(lineWidth: ring, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 220, height: 220).position(x: 399, y: 399)
        if detail == .full {
            box(648, 510, 34, 230, 17, Color.white)
            box(702, 360, 34, 380, 17, Color.white)
            box(756, 440, 34, 300, 17, Color.white)
        } else {
            box(693, 360, 52, 380, 26, Color.white)
        }
        let points: [CGPoint] = detail == .full
            ? [.init(x: 255, y: 760), .init(x: 325, y: 705), .init(x: 390, y: 738), .init(x: 465, y: 665), .init(x: 545, y: 700)]
            : [.init(x: 255, y: 756), .init(x: 340, y: 700), .init(x: 420, y: 734), .init(x: 545, y: 668)]
        Path { $0.addLines(points) }
            .stroke(.white, style: StrokeStyle(lineWidth: detail == .full ? 30 : 44, lineCap: .round, lineJoin: .round))
    }
}

/// The mark, 18 units square, in black: the app loads it as a template and tints it.
struct Glyph: View {
    var body: some View {
        let u: CGFloat = 1024 / 18
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4.5 * u, style: .continuous)
                .stroke(.black, lineWidth: 1.5 * u)
                .frame(width: 16.5 * u, height: 16.5 * u).position(x: 9 * u, y: 9 * u)
            box(3.5 * u, 3.5 * u, 6 * u, 6 * u, 1.75 * u, Color.black)
            box(11 * u, 3.5 * u, 3.5 * u, 11 * u, 1.75 * u, Color.black)
            box(3.5 * u, 11 * u, 6 * u, 3.5 * u, 1.75 * u, Color.black)
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
            let detail: Detail = pixels <= 32 ? .tiny : pixels <= 64 ? .small : .full
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            write(Icon(detail: detail), pixels: pixels, to: iconset.appendingPathComponent(name))
        }
    }
    write(Glyph(), pixels: 1024, to: URL(fileURLWithPath: "Sources/AirStatUI/Resources/Logo.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", "Resources/AppIcon.icns", iconset.path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("Wrote Resources/AppIcon.icns and Sources/AirStatUI/Resources/Logo.png")
