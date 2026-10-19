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

    /// The sizes the card is drawn well at. An action is a button, one cell or two. The
    /// network, the SSD and the battery have little to fill the tallest and widest cards
    /// with, so they stop short of them.
    public var sizes: [BentoTileSize] {
        switch self {
        case .settings, .quit: return [.small, .wide]
        case .network, .disk: return [.small, .wide, .tall, .large, .wideLarge]
        case .battery: return [.small, .wide, .tall, .large]
        default: return BentoTileSize.allCases
        }
    }

    /// The ways the card can draw itself at `size`.
    ///
    /// An action has nothing to count, so it has none, and the system card has no
    /// history to chart. The CPU's load as a lone number reads on a small card and looks
    /// lost on a large one, where the chip says it better. Some sizes offer an extra way:
    /// the network's and the battery's object beside their chart, and on a one-cell
    /// battery its charge written inside it.
    public func styles(for size: BentoTileSize) -> [BentoTileStyle] {
        switch self {
        case .settings, .quit:
            return []
        case .system:
            return [.graphic, .number]
        case .cpu:
            return [.small, .wide, .tall].contains(size) ? [.graphic, .number, .chart] : [.graphic, .chart]
        case .network:
            return size == .large ? [.graphic, .graphicChart, .number, .chart] : [.graphic, .number, .chart]
        case .battery:
            switch size {
            case .small: return [.graphic, .inset, .graphicChart, .number, .chart]
            case .wide: return [.graphic, .graphicChart, .number, .chart]
            default: return [.graphic, .number, .chart]
            }
        default:
            return [.graphic, .number, .chart]
        }
    }

    /// Every style the card offers at one size or another.
    public var styles: [BentoTileStyle] {
        BentoTileStyle.allCases.filter { style in sizes.contains { styles(for: $0).contains(style) } }
    }

    /// The card a new one of this kind starts as.
    public var defaultSize: BentoTileSize {
        switch self {
        case .cpu, .memory, .gpu: return .large
        case .thermal: return .tall
        case .settings, .quit: return .small
        default: return .wide
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

/// How a module card draws itself.
public enum BentoTileStyle: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    /// The object: the chip, the memory stick, the thermometer.
    case graphic
    /// The reading as a big number.
    case number
    /// The reading over the last while, as a line.
    case chart
    /// The object beside or over its chart.
    case graphicChart
    /// The reading written inside the object: the battery's charge in the battery.
    case inset

    public var label: String {
        switch self {
        case .graphic: return "Graphic"
        case .number: return "Number"
        case .chart: return "Chart"
        case .graphicChart: return "Graphic + Chart"
        case .inset: return "Number Inside"
        }
    }
}

/// One card of the bento panel.
public struct BentoTile: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var kind: BentoTileKind
    public var size: BentoTileSize
    public var style: BentoTileStyle

    public init(id: UUID = UUID(), kind: BentoTileKind, size: BentoTileSize? = nil,
                style: BentoTileStyle = .graphic) {
        self.id = id
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.style = style
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
        (BentoTileKind.cpu, BentoTileSize.large), (.memory, .large), (.disk, .wide),
        (.battery, .wide), (.gpu, .large), (.network, .wide), (.thermal, .tall),
        (.settings, .small), (.system, .wide), (.quit, .small),
    ].enumerated().map { index, tile in
        BentoTile(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                  kind: tile.0, size: tile.1)
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

    /// A stored arrangement made safe to draw: sizes each kind can take, and Settings
    /// and Quit always present, since without them the panel has no way out.
    public static func sanitized(_ tiles: [BentoTile]) -> [BentoTile] {
        var result = tiles.map { tile -> BentoTile in
            var tile = tile
            if !tile.kind.sizes.contains(tile.size) { tile.size = tile.kind.defaultSize }
            let styles = tile.kind.styles(for: tile.size)
            if !styles.isEmpty, !styles.contains(tile.style) { tile.style = .graphic }
            return tile
        }
        for action in [BentoTileKind.settings, .quit] where !result.contains(where: { $0.kind == action }) {
            result.append(BentoTile(kind: action))
        }
        return result
    }
}
