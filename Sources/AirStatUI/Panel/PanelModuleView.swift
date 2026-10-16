import SwiftUI
import AppKit
import AirStatKit

/// The one-glance answer for a module, shown on its header line.
///
/// Everything below the header is detail the user reads second; this is what they
/// read first, so each module contributes exactly one of them.
struct PanelSummary {
    /// Whether the primary reads as a measurement or as a state. A state ("Nominal",
    /// "AC") set at headline size looks like a mistake, so it drops to value size.
    enum Emphasis { case measurement, state }

    var value: String?
    var caption: String?
    /// Replaces the module's own glyph. A full battery icon on a Mac that has no
    /// battery states something untrue before the reader gets to the words.
    var icon: String?
    var symbol: String?
    var emphasis: Emphasis = .measurement
    /// How full the module is, 0...1, for the modules a row draws as a `PanelMeter`.
    var fraction: Double?
    var isCharging = false
}

/// One module of the panel: a row that carries the headline value, or the same header
/// over the module's detail in the window beside the panel.
struct PanelModuleView: View {
    /// A row in the list style, the detail shown beside the panel while a row or card
    /// is hovered, or a row in the original style, which unfolds its detail under it.
    enum Presentation { case row, detail, accordion }

    let module: PanelModule
    let engine: MetricsEngine
    let settings: SettingsStore
    var layout: PanelLayoutState?
    var presentation: Presentation = .row
    /// Width of the qualifier column beside the headline value, shared by every row so
    /// the numbers keep one right edge. See `PanelSummary.captionColumnWidth(for:)`.
    var captionColumnWidth: CGFloat

    @State private var isHovering = false
    /// Where this row sits in the panel, so the detail can open level with it.
    @State private var rowFrame: CGRect = .zero
    /// Which window the module's history chart shows, once the user has picked one.
    /// View state rather than a setting: it is a glance choice, and it resets with
    /// the panel. Nil lets the chart choose by how much of the day exists.
    @State var historyRange: HistoryRange?

    /// Derived from the store rather than read from the environment so a module is
    /// correct wherever it is hosted, and injected below so the primitives it draws
    /// cannot disagree with it.
    var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var isAccordion: Bool { presentation == .accordion }

    /// Whether an original-style row is unfolded.
    var isExpanded: Bool {
        let collapsed = layout?.collapsedModulesOverride
            ?? settings.settings.panel.collapsedModules
        return !collapsed.contains(module)
    }

    var showsDetail: Bool {
        switch presentation {
        case .row: false
        case .detail: true
        case .accordion: isExpanded
        }
    }

    /// What the panel fills its bars and core cells with.
    ///
    /// The label colour, not `Palette.metric`. Nine modules each in their own hue is
    /// nine colours competing in a 340pt window, and the bar is the content here —
    /// nothing sits on top of it — so it takes the colour text takes.
    static let barTint = Design.Palette.primaryText

    var tint: Color { Self.barTint }

    /// The history chart stays a step quieter than the bars: a stroked line reads at
    /// secondary weight where a filled bar does not.
    var chartTint: Color { Design.Palette.secondaryText }

    /// The low-to-high band of the history chart, under its mean line. Fainter than
    /// a bar's fill: it is context for the line, not a reading of its own.
    var bandTint: Color { Design.Palette.primaryText.opacity(0.10) }

    /// A module glyph is a thin shape beside a heading it does not compete with, so it
    /// sits at secondary weight — nine icons at full strength is a wall.
    private var iconColor: Color { Design.Palette.secondaryText }

    /// Reserved width for the process list's value column, sized for the widest
    /// reading it can hold ("412.6%", "4.3 GB") so the column never reflows as
    /// processes come and go.
    static let processValueWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            detail
                .padding(.horizontal, Design.Space.panelInset)
                .padding(.top, Design.Space.xxs)
        }
        .padding(.vertical, Design.Space.xxs)
        .environment(\.metricFormatter, formatter)
        .environment(\.isDisclosureInProgress, layout?.isDisclosureTransitionActive == true)
        // The whole row reports hover, padding included, so the pointer never falls
        // into a gap between two rows on its way down the list.
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowFrame = $0 }
        .onContinuousHover { phase in
            // Only a list row opens the detail beside the panel; an original-style row
            // unfolds its own.
            guard presentation == .row else { return }
            switch phase {
            case .active: layout?.rowHover?(module, rowFrame)
            case .ended: layout?.rowHover?(module, nil)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if isAccordion {
            Button(action: toggleCollapsed) {
                headerLine.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(Design.Motion.respectingAccessibility(Design.Motion.hover)) {
                    isHovering = hovering
                }
            }
            .accessibilityLabel(module.label)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")
        } else {
            headerLine
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(module.label)
                .accessibilityValue(accessibilityValue)
        }
    }

    private var accessibilityValue: String {
        isCollecting ? "Collecting" : summary.value ?? ""
    }

    private var headerLine: some View {
        // The hidden digit holds every row at the height a headline number gives it, so
        // a row drawn as a meter, or one still waiting for its first reading, keeps the
        // same rhythm as a row with a number, and nothing moves when a value arrives.
        ZStack {
            Text("0").font(Design.Text.headline).hidden()
            headerContent
        }
        .padding(.horizontal, Design.Space.panelInset)
        .background(hoverHighlight)
    }

    private var headerContent: some View {
        HStack(spacing: Design.Space.m) {
            if isAccordion {
                Image(systemName: "chevron.right")
                    .font(Design.Text.micro.weight(.semibold))
                    .foregroundStyle(Design.Palette.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: Design.Space.m)
            }
            // The spinner takes the glyph's slot rather than a slot of its own, so the
            // label beside it stays where it is.
            Group {
                if isCollecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: summary.icon ?? module.symbolName)
                        .font(Design.Text.sectionHeader)
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: Design.Space.xl)
            Text(module.label)
                .font(Design.Text.sectionHeader)
                .foregroundStyle(Design.Palette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: Design.Space.s)
            if presentation == .row, let fraction = summary.fraction {
                PanelMeter(module: module, fraction: fraction, isCharging: summary.isCharging)
            } else {
                headlineValue
                    // The number outranks the gap in front of it: without this the
                    // `HStack` splits any shortfall between the `Spacer` and the value,
                    // so "7.4 GB" could render as "7.4…" with slack sitting unused to
                    // its left.
                    .layoutPriority(1)
            }
        }
    }

    var isCollecting: Bool { engine.isCollecting(module) }

    /// A list row's follows the detail rather than the pointer, the way a menu item stays
    /// lit while its submenu is open, so the row stays marked as the pointer crosses to
    /// the detail. An original-style row's follows the pointer.
    private var hoverHighlight: some View {
        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
            .fill(isHighlighted ? Design.Palette.track : .clear)
            .padding(.horizontal, Design.Space.s)
    }

    private var isHighlighted: Bool {
        guard isAccordion else { return layout?.detailModule == module }
        // Rows move under a stationary pointer during disclosure. Hiding the
        // highlight while they travel prevents it flashing from one row to the
        // next; onHover still tracks the final row underneath for the next frame.
        return isHovering && layout?.isDisclosureTransitionActive != true
    }

    private func toggleCollapsed() {
        if let coordinate = layout?.toggleModule {
            coordinate(module)
            return
        }
        withAnimation(Design.Motion.respectingAccessibility(Design.Motion.disclosure)) {
            settings.update { s in
                s.panel.collapsedModules = s.panel.collapsedModules(toggling: module)
            }
        }
    }

    @ViewBuilder
    private var headlineValue: some View {
        if let value = summary.value {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.xs) {
                if let symbol = summary.symbol {
                    Image(systemName: symbol)
                        .font(Design.Text.caption.weight(.semibold))
                        .foregroundStyle(Design.Palette.secondaryText)
                }
                Text(value)
                    .font(summary.emphasis == .measurement ? Design.Text.headline : Design.Text.value)
                    .foregroundStyle(Design.Palette.primaryText)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                // The qualifier sits in a shared column so it cannot push the number.
                //
                // Inline, a caption shifted its value left by its own width, so across the
                // collapsed list the numbers ended at x = 254, 282, 285, 300, 323, 324 —
                // a 70pt ragged spread that made the column impossible to scan even though
                // the right edge looked tidy. Every row takes the slot whether or not it
                // has a caption, which puts every number's right edge on the same line.
                // When no row has one there is no column at all.
                if captionColumnWidth > 0 {
                    Text(summary.caption ?? "")
                        .font(Design.Text.caption)
                        .foregroundStyle(Design.Palette.tertiaryText)
                        .lineLimit(1)
                        .frame(width: captionColumnWidth, alignment: .leading)
                        .accessibilityHidden(summary.caption == nil)
                }
            }
        }
    }

    // MARK: Summary

    private var summary: PanelSummary {
        .make(for: module, engine: engine, formatter: formatter)
    }

}

extension MetricsEngine {
    /// Whether `module` is waiting for its first reading since sampling started, which
    /// for a collector that measures rates is the first sample after every pause.
    func isCollecting(_ module: PanelModule) -> Bool {
        switch module {
        case .cpu: cpu.failure == .pending
        case .memory: memory.failure == .pending
        case .gpu: gpu.failure == .pending
        case .network: network.failure == .pending
        case .disk: disk.failure == .pending
        case .battery: power.failure == .pending
        case .thermal: thermal.failure == .pending
        case .processes: processes.failure == .pending
        case .system: system.failure == .pending
        }
    }
}

extension PanelSummary {
    /// The one-glance answer for `module`, or an empty summary while it has nothing yet.
    @MainActor
    static func make(for module: PanelModule, engine: MetricsEngine,
                     formatter: MetricFormatter) -> PanelSummary {
        switch module {
        case .cpu:
            guard let cpu = engine.cpu.value else { return PanelSummary() }
            return PanelSummary(value: formatter.percent(cpu.total.busy),
                                fraction: cpu.total.busy)
        case .memory:
            guard let memory = engine.memory.value else { return PanelSummary() }
            return PanelSummary(value: formatter.memory(memory.usedBytes),
                                caption: "used",
                                fraction: memory.totalBytes > 0
                                    ? Double(memory.usedBytes) / Double(memory.totalBytes) : nil)
        case .gpu:
            guard let gpu = engine.gpu.value, let device = gpu.primary else { return PanelSummary() }
            guard let utilization = device.utilization else {
                return PanelSummary(value: device.name, emphasis: .state)
            }
            return PanelSummary(value: formatter.percent(utilization),
                                // Device identity belongs in the expanded detail: it is
                                // the only caption long enough to break the column.
                                caption: nil,
                                fraction: utilization)
        case .network:
            guard let network = engine.network.value else { return PanelSummary() }
            // The Wi-Fi row below already names the connection; the caption is only
            // needed when there is no signal row to carry it.
            return PanelSummary(value: formatter.networkRate(network.downloadBytesPerSecond),
                                caption: network.wifi == nil ? network.connectionType.label : nil,
                                symbol: "arrow.down")
        case .disk:
            guard let disk = engine.disk.value, let root = disk.rootVolume else { return PanelSummary() }
            return PanelSummary(value: formatter.storage(root.availableBytes),
                                caption: "free",
                                fraction: root.usedFraction)
        case .battery:
            guard let power = engine.power.value else { return PanelSummary() }
            guard power.hasBattery, let percentage = power.percentage else {
                return PanelSummary(value: power.isPluggedIn ? "AC" : MetricFormatter.unavailable,
                                    icon: "powerplug",
                                    emphasis: .state)
            }
            return PanelSummary(value: formatter.percentValue(percentage),
                                caption: power.isCharging ? "charging" : nil,
                                fraction: percentage / 100,
                                isCharging: power.isCharging)
        case .thermal:
            guard let thermal = engine.thermal.value else { return PanelSummary() }
            guard let celsius = thermal.cpuCelsius else {
                return PanelSummary(value: thermal.pressure.label,
                                    emphasis: .state)
            }
            // The thermometer reads 30°C at empty and 100°C at full: roughly an idle
            // die to the point Apple silicon starts throttling.
            return PanelSummary(value: formatter.temperature(celsius),
                                fraction: min(max((celsius - 30) / 70, 0), 1))
        case .processes:
            guard let processes = engine.processes.value else { return PanelSummary() }
            return PanelSummary(value: formatter.count(processes.totalProcessCount),
                                caption: "running")
        case .system:
            guard let system = engine.system.value else { return PanelSummary() }
            return PanelSummary(value: formatter.uptime(system.uptime), caption: "uptime")
        }
    }

    /// The width the qualifier column needs to hold the widest caption in `summaries`.
    ///
    /// Measured from what is on screen rather than reserved for the longest caption the
    /// panel can ever show: sized for "charging", the column stood mostly empty on any
    /// Mac that was not charging and the whole right edge read as a gap. Every row still
    /// takes the same width, so the numbers keep their shared right edge; that edge
    /// just sits where the captions actually end.
    static func captionColumnWidth(for summaries: [PanelSummary]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: Design.Text.captionSize)
        let widest = summaries.compactMap(\.caption).map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return ceil(widest)
    }
}
