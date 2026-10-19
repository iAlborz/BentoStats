import SwiftUI
import AirStatKit

/// The debug layout: one bento card in every size it offers the picked style at, drawn
/// from live readings, with the card and its style picked above, so every combination can
/// be looked at.
///
/// The cards are the bento grid's own, packed the same way, so what shows here is what
/// the panel draws. Each is marked with its size. Pointing at one opens its detail.
struct BentoGallery: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?

    @AppStorage("BentoGallery.kind") private var kind: BentoTileKind = .cpu
    @AppStorage("BentoGallery.style") private var style: BentoTileStyle = .graphic

    /// Largest first, so the small ones fill the holes the large ones leave.
    private static let order: [BentoTileSize] = [.extraWide, .large, .tallLarge, .wideLarge, .tall,
                                                  .wide, .small]

    /// The style picked, or the card's first where it has no such style.
    private var shownStyle: BentoTileStyle {
        kind.styles.contains(style) ? style : kind.styles.first ?? .graphic
    }

    /// Every size the card offers the style at.
    private var tiles: [BentoTile] {
        let sizes = Self.order.filter { size in
            kind.sizes.contains(size)
                && (kind.styles(for: size).isEmpty || kind.styles(for: size).contains(shownStyle))
        }
        return sizes.enumerated().map { index, size in
            // Fixed identities, so switching the style redraws the cards rather than
            // replacing them.
            BentoTile(id: UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index))!,
                      kind: kind, size: size, style: shownStyle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Design.Space.s) {
                Picker("Card", selection: $kind) {
                    ForEach(BentoTileKind.allCases, id: \.self) { Text(Self.shortLabel($0)).tag($0) }
                }
                Picker("Style", selection: Binding(get: { shownStyle }, set: { style = $0 })) {
                    ForEach(kind.styles, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(kind.styles.isEmpty)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)
            BentoGrid(engine: engine, settings: settings, layout: layout,
                      showing: tiles, labelsSizes: true)
        }
    }

    private static func shortLabel(_ kind: BentoTileKind) -> String {
        kind == .thermal ? "Temp" : kind.label
    }
}
