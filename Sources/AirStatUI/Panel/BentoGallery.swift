import SwiftUI
import AirStatKit

/// The debug layout: every design of one bento card, drawn from live readings and each
/// marked with its name and size, with the card picked above, so each can be looked at.
///
/// The cards are the bento grid's own, packed the same way, so what shows here is what
/// the panel draws. Pointing at one opens its detail.
struct BentoGallery: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?

    @AppStorage("BentoGallery.kind") private var kind: BentoTileKind = .cpu

    /// Largest first, so the small ones fill the holes the large ones leave.
    private var tiles: [BentoTile] {
        kind.variants
            .sorted { $0.size.columns * $0.size.rows > $1.size.columns * $1.size.rows }
            .enumerated().map { index, variant in
                // Fixed identities, so switching cards redraws them rather than replacing them.
                BentoTile(id: UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index))!,
                          kind: kind, variant: variant)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Card", selection: $kind) {
                ForEach(BentoTileKind.allCases, id: \.self) { Text(Self.shortLabel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)
            // The designs in the order the card's menu lists them; the one under the
            // pointer is named on the card.
            Text(kind.variants.map { "\($0.label) \($0.size.label)" }.joined(separator: "  ·  "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.Palette.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            BentoGrid(engine: engine, settings: settings, layout: layout,
                      showing: tiles, labelsSizes: true)
        }
    }

    private static func shortLabel(_ kind: BentoTileKind) -> String {
        kind == .thermal ? "Temp" : kind.label
    }
}
