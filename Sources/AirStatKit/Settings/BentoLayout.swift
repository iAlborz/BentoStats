import Foundation

/// What a bento card shows: one module, or one of the panel's two actions.
public enum BentoTileKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case cpu, memory, gpu, network, disk, battery, thermal, system, settings, quit

    public var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .disk: return "SSD"
        case .battery: return "Battery"
        case .thermal: return "Temperature"
        case .system: return "System"
        case .settings: return "Settings"
        case .quit: return "Quit"
        }
    }

    /// The module behind the card, nil for an action.
    public var module: PanelModule? {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .gpu: return .gpu
        case .network: return .network
        case .disk: return .disk
        case .battery: return .battery
        case .thermal: return .thermal
        case .system: return .system
        case .settings, .quit: return nil
        }
    }

    public var isAction: Bool { module == nil }

    public var symbolName: String {
        switch self {
        case .settings: return "gearshape.fill"
        case .quit: return "power"
        default: return module?.symbolName ?? "square"
        }
    }

    /// The card's designs, the one it starts as first. Each is drawn as it was designed,
    /// at its own size: two to five per card, rather than every size in every style.
    public var variants: [BentoVariant] {
        BentoVariant.allCases.filter { $0.kind == self }
    }

    public var defaultVariant: BentoVariant { variants[0] }

    /// The sizes the card's designs come in, in the order they are listed.
    public var sizes: [BentoTileSize] {
        variants.reduce(into: []) { sizes, variant in
            if !sizes.contains(variant.size) { sizes.append(variant.size) }
        }
    }
}

/// A card's size in grid cells, columns across by rows down.
public enum BentoTileSize: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case small, wide, tall, large, wideLarge, tallLarge, extraWide

    public var columns: Int {
        switch self {
        case .small, .tall: return 1
        case .wide, .large, .tallLarge: return 2
        case .wideLarge: return 3
        case .extraWide: return 4
        }
    }

    public var rows: Int {
        switch self {
        case .small, .wide: return 1
        case .tall, .large, .wideLarge, .extraWide: return 2
        case .tallLarge: return 3
        }
    }

    /// "2 × 1": across by down, the way the grid is read.
    public var label: String { "\(columns) × \(rows)" }

    /// Of `sizes`, the one nearest `columns` by `rows`, counting a cell either way as one.
    public static func nearest(columns: Int, rows: Int, in sizes: [BentoTileSize]) -> BentoTileSize? {
        sizes.min { a, b in
            let da = abs(a.columns - columns) + abs(a.rows - rows)
            let db = abs(b.columns - columns) + abs(b.rows - rows)
            return da != db ? da < db : a.columns * a.rows < b.columns * b.rows
        }
    }
}

/// One design of one card: what it shows and the size it shows it at.
///
/// Each is laid out by hand for its size, the way the panel's first cards were, rather
/// than put together from parts at whatever size it is given. The first of each card's
/// is the one it starts as, and the one the designed arrangement uses.
public enum BentoVariant: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case cpuChip, cpuChipSmall, cpuLoad, cpuChipHistory
    case memoryModule, memoryStick, memoryPressure, memoryWide
    case gpuDie, gpuDieSmall, gpuLoad, gpuDieHistory
    case networkSpeeds, networkSpeedsSmall, networkHistory
    case diskDrive, diskSpace, diskHistory
    case batteryCharge, batteryInside, batteryHistory, batteryChargeHistory
    case thermalThermometer, thermalSmall, thermalSensors, thermalFans
    case systemAbout, systemUptime, systemDetails
    case settings, settingsWide
    case quit, quitWide

    public var kind: BentoTileKind {
        switch self {
        case .cpuChip, .cpuChipSmall, .cpuLoad, .cpuChipHistory: return .cpu
        case .memoryModule, .memoryStick, .memoryPressure, .memoryWide: return .memory
        case .gpuDie, .gpuDieSmall, .gpuLoad, .gpuDieHistory: return .gpu
        case .networkSpeeds, .networkSpeedsSmall, .networkHistory: return .network
        case .diskDrive, .diskSpace, .diskHistory: return .disk
        case .batteryCharge, .batteryInside, .batteryHistory, .batteryChargeHistory: return .battery
        case .thermalThermometer, .thermalSmall, .thermalSensors, .thermalFans: return .thermal
        case .systemAbout, .systemUptime, .systemDetails: return .system
        case .settings, .settingsWide: return .settings
        case .quit, .quitWide: return .quit
        }
    }

    public var size: BentoTileSize {
        switch self {
        case .cpuChipSmall, .gpuDieSmall, .memoryPressure, .networkSpeedsSmall, .diskSpace,
             .batteryInside, .thermalSmall, .systemUptime, .settings, .quit:
            return .small
        case .cpuLoad, .gpuLoad, .memoryStick, .networkSpeeds, .diskDrive, .batteryCharge,
             .batteryChargeHistory, .thermalFans, .systemAbout, .settingsWide, .quitWide:
            return .wide
        case .thermalThermometer:
            return .tall
        case .cpuChip, .memoryModule, .gpuDie, .networkHistory, .diskHistory, .batteryHistory,
             .thermalSensors, .systemDetails:
            return .large
        case .cpuChipHistory, .memoryWide, .gpuDieHistory:
            return .extraWide
        }
    }

    /// What it shows, for the card's menu in edit mode.
    public var label: String {
        switch self {
        case .cpuChip: return "Chip and Busiest"
        case .cpuChipSmall: return "Chip"
        case .cpuLoad: return "Load"
        case .cpuChipHistory: return "Chip, Load and History"
        case .memoryModule: return "Module and Top Users"
        case .memoryStick: return "Module"
        case .memoryPressure: return "Pressure"
        case .memoryWide: return "Module, Pressure and Top Users"
        case .gpuDie: return "Die and Meters"
        case .gpuDieSmall: return "Die"
        case .gpuLoad: return "Load"
        case .gpuDieHistory: return "Die, Load and History"
        case .networkSpeeds: return "Speeds"
        case .networkSpeedsSmall: return "Speeds, Small"
        case .networkHistory: return "Speeds and History"
        case .diskDrive: return "Drive and Speeds"
        case .diskSpace: return "Space"
        case .diskHistory: return "Drive and History"
        case .batteryCharge: return "Battery"
        case .batteryInside: return "Charge Inside"
        case .batteryHistory: return "Battery and History"
        case .batteryChargeHistory: return "Charge and History"
        case .thermalThermometer: return "Thermometer"
        case .thermalSmall: return "Thermometer, Small"
        case .thermalSensors: return "All Sensors"
        case .thermalFans: return "Fans"
        case .systemAbout: return "Uptime and Model"
        case .systemUptime: return "Uptime"
        case .systemDetails: return "About This Mac"
        case .settings, .quit: return "Small"
        case .settingsWide, .quitWide: return "Wide"
        }
    }
}

/// One card of the bento panel.
public struct BentoTile: Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var kind: BentoTileKind
    public var variant: BentoVariant

    public var size: BentoTileSize { variant.size }

    public init(id: UUID = UUID(), kind: BentoTileKind, variant: BentoVariant? = nil) {
        self.id = id
        self.kind = kind
        self.variant = variant.flatMap { $0.kind == kind ? $0 : nil } ?? kind.defaultVariant
    }
}

extension BentoTile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, variant
        /// Written before designs, when a card was any size in any style.
        case size
    }

    /// A card saved before designs keeps its size where one of its designs has it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(BentoTileKind.self, forKey: .kind)
        if let variant = try? c.decode(BentoVariant.self, forKey: .variant), variant.kind == kind {
            self.variant = variant
        } else if let size = try? c.decode(BentoTileSize.self, forKey: .size) {
            variant = kind.variants.first { $0.size == size } ?? kind.defaultVariant
        } else {
            variant = kind.defaultVariant
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(variant, forKey: .variant)
    }
}

/// Where a card lands in the grid, in cells from the top-left.
public struct BentoPlacement: Sendable, Equatable {
    public var column: Int
    public var row: Int
    public var columns: Int
    public var rows: Int
}

/// The bento panel's arrangement: an ordered list of cards, packed into a grid six
/// cells across.
///
/// Cards are kept in order rather than at coordinates, the way Control Center keeps
/// its controls. Each one goes to the first spot it fits, scanning the rows top to
/// bottom and each row left to right, so a smaller card fills a hole a larger one
/// left. No arrangement can overlap or leave a card hanging off the edge, moving a card
/// is a change of order, and resizing one lets the rest flow around it.
public enum BentoLayout {
    public static let columns = 6

    /// The panel as it was designed:
    ///
    ///     ┌─────────┬─────────┬─────────┐
    ///     │         │         │   SSD   │
    ///     │   CPU   │ Memory  ├─────────┤
    ///     │         │         │ Battery │
    ///     ├─────────┼─────────┼────┬────┤
    ///     │         │  Wi-Fi  │    │ ⚙︎  │
    ///     │   GPU   ├─────────┤Temp├────┤
    ///     │         │ System  │    │ ⏻  │
    ///     └─────────┴─────────┴────┴────┘
    ///
    /// Fixed identifiers, so two default settings compare equal.
    public static let defaultTiles: [BentoTile] = [
        BentoTileKind.cpu, .memory, .disk, .battery, .gpu, .network, .thermal, .settings, .system, .quit,
    ].enumerated().map { index, kind in
        BentoTile(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                  kind: kind)
    }

    /// Each card's place, in the order given, and how many rows the grid needs.
    public static func pack(_ tiles: [BentoTile], columns: Int = columns)
        -> (placements: [UUID: BentoPlacement], rows: Int) {
        var occupied: [[Bool]] = []
        var placements: [UUID: BentoPlacement] = [:]
        func isFree(_ column: Int, _ row: Int, _ width: Int, _ height: Int) -> Bool {
            for r in row..<row + height where r < occupied.count {
                for c in column..<column + width where occupied[r][c] { return false }
            }
            return true
        }
        for tile in tiles {
            let width = min(tile.size.columns, columns)
            let height = tile.size.rows
            var row = 0
            placing: while true {
                for column in 0...(columns - width) where isFree(column, row, width, height) {
                    while occupied.count < row + height {
                        occupied.append(Array(repeating: false, count: columns))
                    }
                    for r in row..<row + height {
                        for c in column..<column + width { occupied[r][c] = true }
                    }
                    placements[tile.id] = BentoPlacement(column: column, row: row,
                                                         columns: width, rows: height)
                    break placing
                }
                row += 1
            }
        }
        return (placements, occupied.count)
    }

    /// A stored arrangement made safe to draw: each card in a design of its own, and
    /// Settings and Quit always present, since without them the panel has no way out.
    public static func sanitized(_ tiles: [BentoTile]) -> [BentoTile] {
        var result = tiles.map { tile -> BentoTile in
            var tile = tile
            if tile.variant.kind != tile.kind { tile.variant = tile.kind.defaultVariant }
            return tile
        }
        for action in [BentoTileKind.settings, .quit] where !result.contains(where: { $0.kind == action }) {
            result.append(BentoTile(kind: action))
        }
        return result
    }
}
