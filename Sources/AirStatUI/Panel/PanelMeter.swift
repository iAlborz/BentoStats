import SwiftUI
import AirStatKit

/// A row's reading drawn as how full something is, in a shape that says what is being
/// measured: a chip, a memory stick, a graphics card, a drive, a battery, a thermometer.
///
/// Monochrome like the rest of the panel, so the shape carries the identity rather than
/// a colour. The one exception is a low battery, which goes red the way the system's own
/// battery icon does. Built from shapes, never a `Canvas`: see `PlotShape` for why.
struct PanelMeter: View {
    let module: PanelModule
    /// 0...1.
    let fraction: Double
    var isCharging = false

    static let width: CGFloat = 140
    static let height: CGFloat = 14

    private var fill: Color { Design.Palette.primaryText }
    private var track: Color { Design.Palette.track }
    private var detail: Color { Design.Palette.secondaryText }
    /// The panel's own backdrop colour: what a hole in a meter shows.
    private var cutout: Color { Color(nsColor: PanelWindow.backdropColor) }

    var body: some View {
        meter
            .frame(width: Self.width, height: Self.height)
            .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var meter: some View {
        switch module {
        case .cpu: chip
        case .memory: memoryStick
        case .gpu: graphicsCard
        case .disk: drive
        case .battery: battery
        case .thermal: thermometer
        default: EmptyView()
        }
    }

    // MARK: Shapes

    /// A chip in its package: legs along both long edges, and the notch that marks
    /// pin one cut into the left end.
    private var chip: some View {
        let body = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return ZStack {
            ChipPins().fill(detail)
            ZStack {
                body.fill(track)
                FillRect(fraction: fraction).fill(fill).clipShape(body)
                ChipNotch().fill(cutout).clipShape(body)
            }
            .padding(.vertical, 3)
        }
    }

    /// A module board with its row of contacts underneath, broken by the key notch.
    private var memoryStick: some View {
        let body = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        return VStack(spacing: 1) {
            ZStack {
                body.fill(track)
                FillRect(fraction: fraction).fill(fill).clipShape(body)
            }
            MemoryContacts().fill(detail).frame(height: 3)
        }
    }

    /// A card with its mounting bracket on the left and two fans across the face.
    ///
    /// The fans are drawn in the backdrop's colour, so they read on the fill and on the
    /// empty track alike.
    private var graphicsCard: some View {
        let body = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return HStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 0.75).fill(detail).frame(width: 2.5)
            ZStack {
                body.fill(track)
                FillRect(fraction: fraction).fill(fill).clipShape(body)
                CardFans().stroke(cutout, lineWidth: 1.25)
                CardFans(hubsOnly: true).fill(cutout)
            }
            .padding(.vertical, 0.5)
        }
    }

    /// Capacity in blocks, the way a storage meter fills.
    private var drive: some View {
        ZStack {
            DriveSegments().fill(track)
            FillRect(fraction: fraction).fill(fill).clipShape(DriveSegments())
        }
        .padding(.vertical, 2)
    }

    /// The system battery glyph, stretched: an outlined body, a terminal nub, and the
    /// charge inset inside it.
    private var battery: some View {
        let isLow = fraction <= 0.2 && !isCharging
        return HStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(detail, lineWidth: 1)
                FillRect(fraction: fraction)
                    .fill(isLow ? Color(nsColor: .systemRed) : fill)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .padding(2)
                if isCharging {
                    // Dark over the charge and light over the empty part, like the
                    // system glyph's bolt: two bolts, the dark one masked to the charge.
                    // Both span the whole body, so the mask lines up with the charge.
                    let bolt = Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bolt.foregroundStyle(fill)
                    bolt.foregroundStyle(cutout)
                        .mask(FillRect(fraction: fraction).padding(2))
                }
            }
            RoundedRectangle(cornerRadius: 1).fill(detail).frame(width: 2, height: 5)
        }
    }

    /// A bulb on the left and a graduated tube running from it.
    private var thermometer: some View {
        let tube = Capsule(style: .continuous)
        return HStack(spacing: -3) {
            Circle().fill(fill).frame(width: Self.height - 2, height: Self.height - 2)
            VStack(spacing: 1) {
                ThermometerTicks().fill(detail).frame(height: 2.5)
                ZStack {
                    tube.fill(track)
                    FillRect(fraction: fraction).fill(fill).clipShape(tube)
                }
                .frame(height: 6)
                Color.clear.frame(height: 3.5)
            }
        }
    }
}

// MARK: - Shape primitives

/// The leading `fraction` of a rect, animatable so a new reading slides rather than jumps.
private struct FillRect: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(fraction, 0), 1)
        return Path(CGRect(x: rect.minX, y: rect.minY,
                           width: rect.width * clamped, height: rect.height))
    }
}

/// Legs standing off the top and bottom of a chip whose body is inset 3pt into `rect`.
private struct ChipPins: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pin: CGFloat = 2
        let pitch: CGFloat = 8
        var x = rect.minX + 7
        while x <= rect.maxX - 6 {
            path.addRect(CGRect(x: x - pin / 2, y: rect.minY, width: pin, height: 3))
            path.addRect(CGRect(x: x - pin / 2, y: rect.maxY - 3, width: pin, height: 3))
            x += pitch
        }
        return path
    }
}

/// A half-moon centred on the left edge; only the half inside the body shows.
private struct ChipNotch: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 2.5
        return Path(ellipseIn: CGRect(x: rect.minX - radius, y: rect.midY - radius,
                                      width: radius * 2, height: radius * 2))
    }
}

/// Gold fingers along the bottom edge, with the off-centre key notch real modules have.
private struct MemoryContacts: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let contact: CGFloat = 1.5
        let pitch: CGFloat = 3.5
        let notch = (rect.minX + rect.width * 0.42 - 3)...(rect.minX + rect.width * 0.42 + 3)
        var x = rect.minX + 3
        while x <= rect.maxX - 3 {
            if !notch.contains(x) {
                path.addRect(CGRect(x: x - contact / 2, y: rect.minY, width: contact, height: rect.height))
            }
            x += pitch
        }
        return path
    }
}

/// Two fan rings across the card's face, or just their hubs.
private struct CardFans: Shape {
    var hubsOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let diameter = rect.height - 3
        for position in [0.32, 0.68] {
            let center = CGPoint(x: rect.minX + rect.width * position, y: rect.midY)
            let size = hubsOnly ? 2.5 : diameter
            path.addEllipse(in: CGRect(x: center.x - size / 2, y: center.y - size / 2,
                                       width: size, height: size))
        }
        return path
    }
}

/// Ten equal blocks with gaps between them.
private struct DriveSegments: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = 10
        let gap: CGFloat = 2
        let width = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        for index in 0..<count {
            let x = rect.minX + CGFloat(index) * (width + gap)
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height),
                                cornerSize: CGSize(width: 1.5, height: 1.5), style: .continuous)
        }
        return path
    }
}

/// Graduation marks above the tube, one every tenth of its length.
private struct ThermometerTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 4
        for step in 1...9 {
            let x = rect.minX + inset + (rect.width - inset * 2) * CGFloat(step) / 10
            let height = step == 5 ? rect.height : rect.height * 0.6
            path.addRect(CGRect(x: x - 0.5, y: rect.maxY - height, width: 1, height: height))
        }
        return path
    }
}
