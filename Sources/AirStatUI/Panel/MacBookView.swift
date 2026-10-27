import SwiftUI
import AppKit
import AirStatKit

/// The MacBook style: the inside of a MacBook Pro seen from above with its bottom case
/// off, after the internals wallpapers Basic Apple Guy draws, with every part showing how
/// hard it is working.
///
/// Laid out the way the machine is, but spaced out so each part has room for its
/// reading: the hinge and its vents along the top; a blower fan in each upper corner,
/// spinning with the fan's real speed and blowing through copper fins into the hinge;
/// the logic board between them, with heat pipes running from the fins to the M-series
/// chip in its middle, and the Wi-Fi module and the SSD's flash either side of the chip;
/// then the battery's cells either side of the trackpad, a speaker at each edge, and the
/// ports along the sides.
///
///     ┌── hinge ────────────────── vents ────────────────── hinge ──┐
///     │ ┌ fins ┐  ┌────────────── logic board ──────────────┐ ┌ fins ┐ │
///     │ │ fan  │  │ Wi-Fi  ┌ memory │ chip │ memory ┐  flash │ │ fan  │ │
///     │ ╰──────╯  │ ↓ ↑    └────────────────────────┘  free  │ ╰──────╯ │
///     │   27%     │           CPU     GPU    Memory          │   26%    │
///     │ ┌─┐┌ cells ┐ ┌──────── trackpad ────────┐ ┌ cells ┐┌─┐ │
///     │ └─┘└───────┘ └──────────────────────────┘ └───────┘└─┘ │
///     └──────────────────────────────────────────────────────────┘
///
/// Drawn tone on tone in one neutral, as those wallpapers are drawn in one hue, so the
/// colour on it is the data: the cores lit by their load, the memory and the flash
/// filled by how full they are, the cells by their charge. Every reading sits in clear
/// space beside its part, or on the part's own label where it has one, as a battery cell
/// does. Pointing at a part opens its detail beside the panel, as a bento card does.
/// Built from shapes, never a `Canvas`: see `PlotShape` for why.
struct MacBookView: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?

    private static let size = CGSize(width: 706, height: 500)
    private static let inset: CGFloat = 14
    static let width = size.width + inset * 2

    // Where everything sits, in the machine's own points, mirrored about the middle.
    private static let leftHinge = CGRect(x: 40, y: 16, width: 96, height: 14)
    private static let rightHinge = CGRect(x: 570, y: 16, width: 96, height: 14)
    private static let vent = CGRect(x: 148, y: 17, width: 410, height: 12)
    /// The fin stack above, the housing below it.
    private static let leftFan = CGRect(x: 26, y: 40, width: 140, height: 190)
    private static let rightFan = CGRect(x: 540, y: 40, width: 140, height: 190)
    private static let board = CGRect(x: 178, y: 40, width: 350, height: 258)
    private static let package = CGRect(x: 265, y: 58, width: 176, height: 168)
    private static let die = CGRect(x: 303, y: 64, width: 100, height: 156)
    private static let wifi = CGRect(x: 190, y: 66, width: 56, height: 56)
    private static let flash = CGRect(x: 460, y: 66, width: 56, height: 56)
    private static let leftSpeaker = CGRect(x: 20, y: 310, width: 28, height: 172)
    private static let leftCells = CGRect(x: 58, y: 310, width: 168, height: 172)
    private static let trackpad = CGRect(x: 238, y: 310, width: 230, height: 172)
    private static let rightCells = CGRect(x: 480, y: 310, width: 168, height: 172)
    private static let rightSpeaker = CGRect(x: 658, y: 310, width: 28, height: 172)
    /// Where the readings under the fans and the chip start.
    private static let readingsTop: CGFloat = 238

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            chassis
            hinge
            boardBase
            antennas
            fans
            heatPipes
            chip
            wifiModule
            flashPackages
            readings
            battery
            trackpadInfo
            speakers
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .padding(Self.inset)
        .environment(\.metricFormatter, formatter)
    }

    // MARK: Case

    private var chassis: some View {
        let shell = RoundedRectangle(cornerRadius: 34, style: .continuous)
        let floor = RoundedRectangle(cornerRadius: 27, style: .continuous)
        return canvas {
            shell.fill(LinearGradient(colors: [Tone.rimTop, Tone.rim], startPoint: .top, endPoint: .bottom))
            shell.strokeBorder(Tone.edge, lineWidth: 1)
            floor.fill(Tone.floor).padding(8)
            floor.strokeBorder(Tone.shadow, lineWidth: 1).padding(8)
            ports
        }
    }

    /// Cut into the sides: MagSafe, two Thunderbolt ports and the headphone jack on the
    /// left, HDMI, Thunderbolt and the SD slot on the right.
    private var ports: some View {
        let left = [CGRect(x: 2, y: 96, width: 4, height: 24), CGRect(x: 2, y: 136, width: 4, height: 14),
                    CGRect(x: 2, y: 160, width: 4, height: 14), CGRect(x: 2, y: 192, width: 4, height: 6)]
        let right = [CGRect(x: 700, y: 98, width: 4, height: 20), CGRect(x: 700, y: 136, width: 4, height: 14),
                     CGRect(x: 700, y: 166, width: 4, height: 30)]
        return ForEach(Array((left + right).enumerated()), id: \.offset) { _, rect in
            place(RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Tone.port), rect)
        }
    }

    /// The display's hinges at either end and the exhaust between them. The App Store's
    /// copy, which reads no fan, has macOS's thermal state printed in the middle instead.
    private var hinge: some View {
        let barrel = ZStack {
            Capsule().fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
            Capsule().fill(Tone.shadow).frame(height: 2)
            Capsule().strokeBorder(Tone.edge, lineWidth: 1)
        }
        let state = Capabilities.readsSensors ? nil : engine.thermal.value?.pressure
        return canvas {
            place(barrel, Self.leftHinge)
            place(barrel, Self.rightHinge)
            if let state {
                let gap: CGFloat = 150
                let run = (Self.vent.width - gap) / 2
                place(VentSlots().fill(Tone.vent),
                      CGRect(x: Self.vent.minX, y: Self.vent.minY, width: run, height: Self.vent.height))
                place(VentSlots().fill(Tone.vent),
                      CGRect(x: Self.vent.maxX - run, y: Self.vent.minY, width: run, height: Self.vent.height))
                HStack(spacing: Design.Space.s) {
                    caption("Thermal state")
                    Text(Self.stateWord(state))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gradient(Self.stateColors(state)))
                }
                .fixedSize()
                .hoverRegion(.thermal, layout: layout)
                .position(x: Self.vent.midX, y: Self.vent.midY)
            } else {
                place(VentSlots().fill(Tone.vent), Self.vent)
            }
        }
    }

    // MARK: Fans

    private var fans: some View {
        let fans = engine.thermal.value?.fans ?? []
        return canvas {
            place(fan(fans.first, isMirrored: false).hoverRegion(.thermal, layout: layout), Self.leftFan)
            place(fan(fans.count > 1 ? fans[1] : fans.first, isMirrored: true)
                .hoverRegion(.thermal, layout: layout), Self.rightFan)
        }
    }

    /// The fin stack the fan blows through, and the fan in its housing: square where it
    /// meets the fins, round where it wraps the blades.
    private func fan(_ fan: FanInfo?, isMirrored: Bool) -> some View {
        let fins = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let radius = Self.leftFan.width / 2
        let housing = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: radius,
                                                                bottomTrailing: radius, topTrailing: 6),
                                             style: .circular)
        return VStack(spacing: -2) {
            ZStack {
                fins.fill(Tone.well)
                VentSlots(pitch: 3.2).fill(Copper.fins).padding(.vertical, 2)
                fins.strokeBorder(Tone.edge, lineWidth: 0.75)
            }
            .frame(height: 20)
            ZStack(alignment: .bottom) {
                housing.fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
                housing.strokeBorder(Tone.edge, lineWidth: 1)
                ZStack {
                    Circle().fill(Tone.well)
                    Circle().strokeBorder(Tone.shadow, lineWidth: 1)
                    SpinningFan(fraction: fan?.speedFraction ?? 0, isSpinning: (fan?.currentRPM ?? 0) >= 1,
                                isMirrored: isMirrored)
                        .frame(width: 114, height: 114)
                }
                .frame(width: 124, height: 124)
                .padding(.bottom, radius - 62)
                HStack {
                    screw
                    Spacer()
                    screw
                }
                .padding(.horizontal, 9)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 9)
            }
        }
    }

    // MARK: Board

    private var boardBase: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return canvas {
            place(ZStack {
                shape.fill(LinearGradient(colors: [Tone.boardTop, Tone.board], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Tone.edge, lineWidth: 1)
            }, Self.board)
            BoardParts(kind: .capacitors).fill(Tone.component)
            BoardParts(kind: .chips).fill(Tone.boardChip)
            BoardParts(kind: .chips).stroke(Color.white.opacity(0.14), lineWidth: 0.75)
            ForEach(Array(Self.boardScrews.enumerated()), id: \.offset) { _, point in
                screw.position(point)
            }
        }
    }

    private static let boardScrews = [CGPoint(x: 353, y: 48), CGPoint(x: 190, y: 286), CGPoint(x: 516, y: 286)]

    /// Copper, from along the foot of the fins at each fan's outlet, over the top of the
    /// board and down into the chip, where the package covers their ends.
    private var heatPipes: some View {
        let pipes = [HeatPipe(from: CGPoint(x: 46, y: 57), along: 240, to: CGPoint(x: 292, y: 78)),
                     HeatPipe(from: CGPoint(x: 660, y: 57), along: 466, to: CGPoint(x: 414, y: 78))]
        return canvas {
            ForEach(pipes.indices, id: \.self) { index in
                pipes[index].stroke(Color.black.opacity(0.18),
                                    style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    .offset(y: 1)
                pipes[index].stroke(Copper.pipe, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                pipes[index].stroke(Copper.shine.opacity(0.8),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .offset(y: -2)
            }
        }
    }

    /// The Wi-Fi module's two antenna leads, up into the hinge where the antennas are.
    private var antennas: some View {
        canvas {
            ForEach([Self.wifi.minX + 16, Self.wifi.maxX - 16], id: \.self) { x in
                place(Capsule().fill(Tone.cable), CGRect(x: x - 1, y: Self.vent.maxY, width: 2,
                                                         height: Self.wifi.minY - Self.vent.maxY))
            }
        }
    }

    // MARK: Chip

    /// The M-series package: the die in the middle, its CPU cores over its GPU cores, each
    /// lit by its load, and the memory packages either side, filled by how much is in use.
    private var chip: some View {
        let substrate = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let memory = engine.memory.value
        // Four packages for a Max's wide memory bus, two otherwise.
        let packages = (memory?.totalBytes ?? 0) >= 32 << 30 ? 4 : 2
        return canvas {
            place(ZStack {
                substrate.fill(LinearGradient(colors: [Tone.substrateTop, Tone.substrate],
                                              startPoint: .top, endPoint: .bottom))
                substrate.strokeBorder(Tone.edge, lineWidth: 1)
            }
            .shadow(color: Tone.dropShadow, radius: 3, y: 1), Self.package)
            place(memoryPackages(count: packages, fraction: memory?.usedFraction ?? 0)
                .hoverRegion(.memory, layout: layout), Self.package.insetBy(dx: 6, dy: 6))
            place(die, Self.die)
        }
    }

    private func memoryPackages(count: Int, fraction: Double) -> some View {
        let column = VStack(spacing: 6) {
            ForEach(0..<count / 2, id: \.self) { _ in
                level(fraction, color: palette(.memory)[0], vertical: true, radius: 2.5, face: Tone.chipFace,
                      isChip: true)
                    .frame(width: 26)
            }
        }
        return HStack(spacing: 0) {
            column
            Spacer(minLength: 0)
            column
        }
    }

    private var die: some View {
        let cpu = engine.cpu.value
        let kinds = cpu?.coreKinds ?? []
        let loads = cpu?.perCore.map(\.busy) ?? []
        // A core the system did not classify is drawn as a performance core: that is what
        // a chip without the split has.
        let performance = loads.indices.filter { $0 >= kinds.count || kinds[$0] != .efficiency }.map { loads[$0] }
        let efficiency = loads.indices.filter { $0 < kinds.count && kinds[$0] == .efficiency }.map { loads[$0] }
        let device = engine.gpu.value?.primary
        let gpuCores = device?.coreCount ?? engine.system.value?.gpuCoreCount ?? 0
        let inner = Self.die.width - 16
        return ZStack {
            ChipFace()
            VStack(spacing: 7) {
                ChipGraphic.lettering(engine.system.value?.chipName, size: 64)
                    .frame(height: 34)
                ChipCores(performance: performance, efficiency: efficiency,
                          size: CGSize(width: inner, height: 46),
                          performanceColors: [.white, .white],
                          efficiencyColors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)])
                    .frame(width: inner, height: 46)
                    .hoverRegion(.cpu, layout: layout)
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                gpuGrid(cores: gpuCores, load: device?.utilization ?? 0)
                    .frame(width: inner)
                    .frame(maxHeight: .infinity)
                    .hoverRegion(.gpu, layout: layout)
            }
            .padding(8)
        }
    }

    /// The GPU's cores in two rows, four on the biggest chips, switching on one by one as
    /// the load rises: macOS reports the GPU only as a whole, so the lit ones read as a
    /// level, not as which.
    private func gpuGrid(cores: Int, load: Double) -> some View {
        let rows = cores > 24 ? 4 : cores > 4 ? 2 : 1
        let columns = max(1, Int((Double(cores) / Double(rows)).rounded(.up)))
        let lit = Int((min(max(load, 0), 1) * Double(cores)).rounded())
        return VStack(spacing: 3) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < cores {
                            GPUBlock(isLit: index < lit, colors: palette(.gpu))
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: lit)
    }

    // MARK: Wi-Fi and flash

    /// The Wi-Fi module under its shield, with its antenna leads' connectors along the top.
    private var wifiModule: some View {
        let network = engine.network.value ?? engine.lastKnown.network.value
        let can = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return canvas {
            place(ZStack {
                can.fill(LinearGradient(colors: [Tone.shieldTop, Tone.shield],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                DotGrid(pitch: 5, radius: 0.7).fill(Tone.well.opacity(0.7)).padding(6).clipShape(can)
                Image(systemName: network?.wifi != nil || network == nil ? "wifi" : "network")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(gradient(palette(.network)))
                    .padding(.top, 6)
                can.strokeBorder(Tone.edge, lineWidth: 1)
            }
            .shadow(color: Tone.dropShadow, radius: 2, y: 1)
            .hoverRegion(.network, layout: layout), Self.wifi)
            ForEach([Self.wifi.minX + 16, Self.wifi.maxX - 16], id: \.self) { x in
                ZStack {
                    Circle().fill(Tone.cable)
                    Circle().fill(Copper.shine).frame(width: 2.5, height: 2.5)
                }
                .frame(width: 7, height: 7)
                .position(x: x, y: Self.wifi.minY + 7)
            }
        }
    }

    /// The SSD's flash on the board beside the chip, filled by how full the disk is.
    private var flashPackages: some View {
        let root = engine.disk.value?.rootVolume
        let used = root.map { $0.totalBytes > 0 ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 } ?? 0
        return place(VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { _ in
                level(used, color: palette(.disk)[0], vertical: false, radius: 2.5, face: Tone.chipFace,
                      isChip: true)
            }
        }
        .shadow(color: Tone.dropShadow, radius: 2, y: 1)
        .hoverRegion(.disk, layout: layout), Self.flash)
    }

    // MARK: Readings

    /// Each part's reading in the clear space beside it: under the fans, under the Wi-Fi
    /// module and the flash, and under the chip, one for each of its parts.
    private var readings: some View {
        let thermal = engine.thermal.value
        let fans = thermal?.fans ?? []
        let cpu = engine.cpu.value
        let gpu = engine.gpu.value?.primary
        let memory = engine.memory.value
        let root = engine.disk.value?.rootVolume
        let underChip = Self.readingsTop
        return canvas {
            fanReading(fans.first).hoverRegion(.thermal, layout: layout)
                .top(at: CGPoint(x: Self.leftFan.midX, y: underChip))
            if fans.count > 1 {
                fanReading(fans[1]).hoverRegion(.thermal, layout: layout)
                    .top(at: CGPoint(x: Self.rightFan.midX, y: underChip))
            }
            networkReading.hoverRegion(.network, layout: layout)
                .top(at: CGPoint(x: Self.wifi.midX, y: Self.wifi.maxY + 10))
            reading("SSD", root.map { formatter.storage($0.availableBytes) + " free" }, colors: palette(.disk),
                    size: 12, celsius: Self.hottest(thermal, .storage))
                .hoverRegion(.disk, layout: layout)
                .top(at: CGPoint(x: Self.flash.midX, y: Self.flash.maxY + 10))
            reading("CPU", cpu.map { formatter.percent($0.total.busy) }, colors: palette(.cpu),
                    celsius: thermal?.cpuCelsius)
                .hoverRegion(.cpu, layout: layout)
                .top(at: CGPoint(x: Self.package.midX - 66, y: underChip))
            reading("GPU", gpu?.utilization.map { formatter.percent($0) }, colors: palette(.gpu),
                    celsius: thermal?.gpuCelsius)
                .hoverRegion(.gpu, layout: layout)
                .top(at: CGPoint(x: Self.package.midX, y: underChip))
            reading("Memory", memory.map { formatter.percent($0.usedFraction) }, colors: palette(.memory),
                    detail: memory.map { "of \(formatter.memory($0.totalBytes))" })
                .hoverRegion(.memory, layout: layout)
                .top(at: CGPoint(x: Self.package.midX + 66, y: underChip))
        }
    }

    /// How fast a fan is going. Nothing under a fan the App Store's copy cannot read: its
    /// blades are the drawing's, not a reading.
    @ViewBuilder
    private func fanReading(_ fan: FanInfo?) -> some View {
        if let fan {
            reading(fan.name, fan.currentRPM < 1 ? "Off" : formatter.percent(fan.speedFraction),
                    colors: Self.fanColors, detail: fan.currentRPM < 1 ? nil : formatter.rpm(fan.currentRPM))
        } else if Capabilities.readsSensors {
            reading("Fans", "None", colors: [Design.Palette.secondaryText])
        }
    }

    private var networkReading: some View {
        let network = engine.network.value ?? engine.lastKnown.network.value
        return VStack(spacing: 1) {
            caption(network?.wifi?.ssid ?? (network?.wifi != nil || network == nil ? "Wi-Fi" : "Network"))
                .frame(maxWidth: 80)
            Group {
                Text("↓ " + (network.map { formatter.networkRate($0.downloadBytesPerSecond) } ?? MetricFormatter.unavailable))
                    .foregroundStyle(gradient(Self.downColors))
                Text("↑ " + (network.map { formatter.networkRate($0.uploadBytesPerSecond) } ?? MetricFormatter.unavailable))
                    .foregroundStyle(gradient(Self.upColors))
            }
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .contentTransition(.numericText())
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A part's reading: what it is in small capitals, the figure in the part's colours,
    /// and under it the part's temperature where it has a sensor, or a detail.
    private func reading(_ title: String, _ value: String?, colors: [Color], size: CGFloat = 16,
                         celsius: Double? = nil, detail: String? = nil) -> some View {
        VStack(spacing: 1) {
            caption(title)
            Text(value ?? MetricFormatter.unavailable)
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundStyle(gradient(colors))
                .contentTransition(.numericText())
            if let celsius {
                HStack(spacing: 1) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9, weight: .bold))
                    Text(formatter.temperature(celsius))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(gradient(Self.heatColors))
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Design.Palette.secondaryText)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func caption(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Design.Palette.secondaryText)
            .lineLimit(1)
    }

    // MARK: Battery, trackpad and speakers

    /// Three cells either side of the trackpad, each filled by the pack's charge, red when
    /// low. The middle cell on each side carries the pack's label: the charge on the left,
    /// what the power is doing on the right.
    private var battery: some View {
        let power = engine.power.value
        let charge = (power?.percentage ?? 0) / 100
        let isLow = power != nil && charge <= 0.2 && power?.isCharging == false
        let colors = isLow ? Self.heatColors : palette(.battery)
        let state = power.map(powerState)
        return canvas {
            place(cells(charge: charge, color: colors[0], tabsTrailing: true) {
                reading("Battery", power?.percentage.map { formatter.percentValue($0) }, colors: colors,
                        size: 17, celsius: power?.temperatureCelsius ?? Self.hottest(engine.thermal.value, .battery))
            }
            .hoverRegion(.battery, layout: layout), Self.leftCells)
            place(cells(charge: charge, color: colors[0], tabsTrailing: false) {
                reading(state?.title ?? "Power", state?.value, colors: colors, size: 15)
            }
            .hoverRegion(.battery, layout: layout), Self.rightCells)
        }
    }

    private func cells<Label: View>(charge: Double, color: Color, tabsTrailing: Bool,
                                    @ViewBuilder label: () -> Label) -> some View {
        let sticker = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return VStack(spacing: 8) {
            cell(charge: charge, color: color, tabsTrailing: tabsTrailing)
            cell(charge: charge, color: color, tabsTrailing: tabsTrailing)
                .overlay {
                    label()
                        .padding(.horizontal, Design.Space.l)
                        .padding(.vertical, 5)
                        .background(sticker.fill(Tone.sticker))
                        .overlay(sticker.strokeBorder(Tone.edge, lineWidth: 0.75))
                        .shadow(color: Tone.dropShadow, radius: 1.5, y: 0.5)
                }
            cell(charge: charge, color: color, tabsTrailing: tabsTrailing)
        }
    }

    /// One cell: the pouch, filled with the charge from its outer end, and at the end that
    /// faces the trackpad the strip its tabs come out of.
    private func cell(charge: Double, color: Color, tabsTrailing: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let tabs = ZStack {
            Rectangle().fill(Tone.well)
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(LinearGradient(colors: [Tone.screwTop, Tone.screw], startPoint: .top, endPoint: .bottom))
                        .frame(width: 6, height: 9)
                }
            }
        }
        .frame(width: 13)
        return ZStack {
            shape.fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 0) {
                if !tabsTrailing { tabs }
                ZStack {
                    FillFromLeading(fraction: charge)
                        .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.22)],
                                             startPoint: .leading, endPoint: .trailing))
                    LevelLine(fraction: charge, vertical: false).fill(color)
                }
                .scaleEffect(x: tabsTrailing ? 1 : -1)
                if tabsTrailing { tabs }
            }
            .clipShape(shape)
            shape.strokeBorder(Tone.edge, lineWidth: 1)
        }
        .shadow(color: Tone.dropShadow, radius: 2, y: 1)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: charge)
    }

    /// What the power is doing, and for how long, where the system says.
    private func powerState(_ power: PowerSnapshot) -> (title: String, value: String) {
        guard power.hasBattery else { return ("Power", "Adapter") }
        if power.isCharging {
            return power.timeToFull.map { ("Charging", "Full in \(formatter.duration($0))") } ?? ("Power", "Charging")
        }
        if power.isFullyCharged { return ("Power", "Charged") }
        if power.isPluggedIn { return ("Power", "Plugged in") }
        return power.timeToEmpty.map { ("On battery", "\(formatter.duration($0)) left") } ?? ("Power", "On battery")
    }

    /// The trackpad, with what the machine is written on it.
    private var trackpadInfo: some View {
        let system = engine.system.value
        let model = system.map(BentoGrid.model)
        let pad = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return place(ZStack {
            pad.fill(LinearGradient(colors: [Tone.glassTop, Tone.glass], startPoint: .top, endPoint: .bottom))
            pad.strokeBorder(Tone.edge, lineWidth: 1)
            VStack(spacing: 3) {
                Text(model?.name ?? "MacBook")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.Palette.primaryText)
                if let detail = model?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Design.Palette.secondaryText)
                }
                if let system {
                    Text("\(system.osName) \(system.osVersion)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Design.Palette.secondaryText)
                    Text("Up \(formatter.uptime(system.uptime))")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Design.Palette.tertiaryText)
                        .padding(.top, 4)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Design.Space.l)
        }
        .shadow(color: Tone.dropShadow, radius: 2, y: 1)
        .hoverRegion(.system, layout: layout), Self.trackpad)
    }

    private var speakers: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let speaker = ZStack {
            shape.fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
            DotGrid(pitch: 5, radius: 1.1).fill(Tone.well).padding(6)
            shape.strokeBorder(Tone.edge, lineWidth: 1)
        }
        return canvas {
            place(speaker, Self.leftSpeaker)
            place(speaker, Self.rightSpeaker)
        }
    }

    // MARK: Pieces

    /// What holds a part down.
    private var screw: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Tone.screwTop, Tone.screw], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Tone.edge, lineWidth: 0.75)
            Circle().fill(Tone.well).frame(width: 3.5, height: 3.5)
        }
        .frame(width: 9, height: 9)
    }

    /// How full a part is, tone on tone: a wash of its colour up to the level, and a
    /// bright line at the level itself. A chip carries the dot that marks its first pin.
    private func level(_ fraction: Double, color: Color, vertical: Bool, radius: CGFloat,
                       face: Color, isChip: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(face)
            Group {
                if vertical {
                    FillFromBottom(fraction: fraction).fill(color.opacity(0.45))
                    LevelLine(fraction: fraction, vertical: true).fill(color)
                } else {
                    FillFromLeading(fraction: fraction).fill(color.opacity(0.45))
                    LevelLine(fraction: fraction, vertical: false).fill(color)
                }
            }
            .clipShape(shape)
            if isChip {
                Circle().fill(Color.white.opacity(0.3))
                    .frame(width: 3, height: 3)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }

    /// The whole machine's area, for layers drawn in its own points.
    private func canvas<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading, content: content)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    /// Sets a part at its place by layout rather than by offset, so the frame it reports
    /// for the detail beside the panel is where it is drawn.
    private func place<V: View>(_ view: V, _ rect: CGRect) -> some View {
        view.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }

    private func palette(_ module: PanelModule) -> [Color] {
        BentoGrid.palette(module)
    }

    private func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private static let fanColors = [Color(nsColor: .systemCyan), Color(nsColor: .systemBlue)]
    private static let heatColors = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]
    private static let upColors = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]
    private static let downColors = [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)]

    private static func hottest(_ thermal: ThermalSnapshot?, _ category: SensorCategory) -> Double? {
        thermal?.sensors.filter { $0.category == category }.map(\.celsius).max()
    }

    /// The bento's words and colours for macOS's thermal states.
    private static func stateWord(_ state: ThermalPressure) -> String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Elevated"
        case .serious: "High"
        case .critical: "Critical"
        }
    }

    private static func stateColors(_ state: ThermalPressure) -> [Color] {
        switch state {
        case .nominal: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)]
        case .fair: [Color(nsColor: .systemYellow), Color(nsColor: .systemOrange)]
        case .serious: [Color(nsColor: .systemOrange), Color(nsColor: .systemRed)]
        case .critical: [Color(nsColor: .systemRed), Color(nsColor: .systemPink)]
        }
    }

    /// One neutral in steps, light aluminium or dark graphite, for everything that is
    /// not data.
    private enum Tone {
        private static func shade(light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                NSColor(white: appearance.isDark ? dark : light, alpha: alpha)
            })
        }

        private static func ink(light: CGFloat, dark: CGFloat) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
            })
        }

        static let rimTop = shade(light: 0.86, dark: 0.24)
        static let rim = shade(light: 0.76, dark: 0.16)
        static let floor = shade(light: 0.93, dark: 0.095)
        static let boardTop = shade(light: 0.85, dark: 0.165)
        static let board = shade(light: 0.81, dark: 0.14)
        static let partTop = shade(light: 0.82, dark: 0.235)
        static let part = shade(light: 0.75, dark: 0.195)
        static let well = shade(light: 0.62, dark: 0.11)
        static let substrateTop = shade(light: 0.36, dark: 0.29)
        static let substrate = shade(light: 0.27, dark: 0.23)
        static let chipFace = shade(light: 0.13, dark: 0.08)
        static let shieldTop = shade(light: 0.93, dark: 0.42)
        static let shield = shade(light: 0.74, dark: 0.27)
        static let glassTop = shade(light: 0.97, dark: 0.15)
        static let glass = shade(light: 0.90, dark: 0.115)
        static let sticker = shade(light: 0.98, dark: 0.15, alpha: 0.94)
        static let screwTop = shade(light: 0.88, dark: 0.48)
        static let screw = shade(light: 0.66, dark: 0.30)
        static let component = shade(light: 0.68, dark: 0.25)
        static let boardChip = shade(light: 0.30, dark: 0.10)
        static let cable = shade(light: 0.45, dark: 0.32)
        static let vent = shade(light: 0.6, dark: 0.03)
        static let port = shade(light: 0.18, dark: 0.02)
        static let edge = ink(light: 0.12, dark: 0.13)
        static let shadow = ink(light: 0.10, dark: 0)
        static let dropShadow = Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: 0, alpha: appearance.isDark ? 0.45 : 0.16)
        })
    }

    /// The heat pipes and the fins they run through.
    private enum Copper {
        static let pipe = LinearGradient(colors: [Color(red: 0.86, green: 0.55, blue: 0.32),
                                                  Color(red: 0.66, green: 0.38, blue: 0.20)],
                                         startPoint: .top, endPoint: .bottom)
        static let shine = Color(red: 0.98, green: 0.76, blue: 0.55)
        static let fins = LinearGradient(colors: [Color(red: 0.85, green: 0.58, blue: 0.38),
                                                  Color(red: 0.60, green: 0.36, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom)
    }
}

private extension View {
    /// Sets a reading with the middle of its top edge at `point`, so readings of one,
    /// two or three lines line up along their tops.
    func top(at point: CGPoint) -> some View {
        frame(width: 160, height: 80, alignment: .top)
            .position(x: point.x, y: point.y + 40)
    }
}

// MARK: - Hover

extension View {
    /// Reports the pointer over a part the way a bento card does, so the part's detail
    /// opens beside the panel, and rings the part while it is open.
    func hoverRegion(_ module: PanelModule, layout: PanelLayoutState?) -> some View {
        modifier(HoverRegion(module: module, layout: layout))
    }
}

private struct HoverRegion: ViewModifier {
    let module: PanelModule
    let layout: PanelLayoutState?
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active: layout?.rowHover?(module, frame)
                case .ended: layout?.rowHover?(module, nil)
                }
            }
    }
}

// MARK: - Shapes

/// A fan's blades, curved, turning at a pace set by how fast the real fan is running:
/// a slow drift at idle, a blur at full speed, still when the fan is stopped.
///
/// A Mac's two fans are drawn as each other's reflection: the second one's blades curve
/// the other way, and it turns anticlockwise.
struct SpinningFan: View {
    /// 0...1, idle to flat out.
    let fraction: Double
    let isSpinning: Bool
    var isMirrored = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per turn, in steps, so a fan that wavers by a few RPM keeps its pace.
    private var period: Double {
        let step = (min(max(fraction, 0), 1) * 6).rounded() / 6
        return 2.6 - 2.1 * step
    }

    var body: some View {
        let period = isSpinning && !reduceMotion ? self.period : nil
        // A new rotor at each new pace, which starts turning from rest. The angle cannot
        // live here: set back to 0 and on to 360 in one update, it would not change at
        // all, and the fan would stop at the first change of pace.
        FanRotor(period: period, isMirrored: isMirrored)
            .id(period ?? 0)
    }
}

private struct FanRotor: View {
    let period: Double?
    let isMirrored: Bool

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            FanBlades().fill(Color.white.opacity(0.38))
            FanBlades().stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            Circle().fill(Color(white: 0.35)).frame(width: 34, height: 34)
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1).frame(width: 34, height: 34)
        }
        .scaleEffect(x: isMirrored ? -1 : 1)
        .rotationEffect(.degrees(angle))
        .onAppear {
            guard let period else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                angle = isMirrored ? -360 : 360
            }
        }
    }
}

private struct FanBlades: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner: CGFloat = 18
        let count = 23
        for index in 0..<count {
            let a = Double(index) / Double(count) * 2 * .pi
            let sweep = 0.38
            func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
                CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            }
            path.move(to: point(inner, a))
            path.addQuadCurve(to: point(outer, a + sweep), control: point(outer * 0.62, a + sweep * 0.15))
            path.addLine(to: point(outer, a + sweep + 0.07))
            path.addQuadCurve(to: point(inner, a + 0.1), control: point(outer * 0.6, a + sweep * 0.3))
            path.closeSubpath()
        }
        return path
    }
}

/// A heat pipe: straight along from the fins to `along`, then curving down into the chip.
private struct HeatPipe: Shape {
    let from: CGPoint
    let along: CGFloat
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: along, y: from.y))
        path.addQuadCurve(to: to, control: CGPoint(x: to.x, y: from.y))
        return path
    }
}

/// Slots side by side: the exhaust along the hinge, or a fan's fins.
private struct VentSlots: Shape {
    var pitch: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = pitch * 0.42
        var x = rect.minX + 2
        while x < rect.maxX - 2 {
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height),
                                cornerSize: CGSize(width: width / 2.5, height: width / 2.5))
            x += pitch
        }
        return path
    }
}

/// A bright line where a fill ends, across a part filling from the bottom, or down one
/// filling from the left.
private struct LevelLine: Shape {
    var fraction: Double
    let vertical: Bool
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = CGFloat(min(max(fraction, 0), 1))
        guard f > 0 else { return Path() }
        if vertical {
            return Path(CGRect(x: rect.minX, y: rect.maxY - rect.height * f, width: rect.width, height: 2))
        }
        return Path(CGRect(x: rect.minX + rect.width * f - 2, y: rect.minY, width: 2, height: rect.height))
    }
}

/// The small parts around a logic board's big ones, at fixed places so the board looks
/// the same every time it is drawn: a column of capacitors either side of the chip, and
/// the power controllers in the board's lower corners with capacitors beside them.
private struct BoardParts: Shape {
    enum Kind { case chips, capacitors }

    let kind: Kind

    /// In the machine's points, the left half; the right half mirrors it.
    private static let chips = [CGRect(x: 194, y: 196, width: 30, height: 30),
                                CGRect(x: 232, y: 202, width: 18, height: 12),
                                CGRect(x: 194, y: 238, width: 18, height: 14)]
    private static let width: CGFloat = 706

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func add(_ part: CGRect, radius: CGFloat) {
            for frame in [part, CGRect(x: Self.width - part.maxX, y: part.minY, width: part.width,
                                       height: part.height)] {
                path.addRoundedRect(in: frame, cornerSize: CGSize(width: radius, height: radius))
            }
        }
        guard kind == .capacitors else {
            for chip in Self.chips { add(chip, radius: 1.5) }
            return path
        }
        for y in stride(from: CGFloat(70), through: 214, by: 9) {
            add(CGRect(x: 258, y: y, width: 4, height: 2.5), radius: 0.5)
        }
        for x in stride(from: CGFloat(218), through: 246, by: 7) {
            add(CGRect(x: x, y: 240, width: 2.5, height: 4), radius: 0.5)
            add(CGRect(x: x, y: 248, width: 2.5, height: 4), radius: 0.5)
        }
        return path
    }
}

/// Holes in rows, each row half a pitch along from the last: a speaker's grille, or the
/// vents in a shield.
private struct DotGrid: Shape {
    let pitch: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var row = 0
        var y = rect.minY + radius
        while y <= rect.maxY - radius {
            var x = rect.minX + radius + (row.isMultiple(of: 2) ? 0 : pitch / 2)
            while x <= rect.maxX - radius {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += pitch
            }
            y += pitch * 0.87
            row += 1
        }
        return path
    }
}

/// The bottom `fraction` of a rect.
private struct FillFromBottom: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height = rect.height * min(max(fraction, 0), 1)
        return Path(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
    }
}

/// The leading `fraction` of a rect.
private struct FillFromLeading: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * min(max(fraction, 0), 1),
                    height: rect.height))
    }
}
