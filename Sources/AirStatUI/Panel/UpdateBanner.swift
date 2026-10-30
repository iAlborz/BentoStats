import SwiftUI
import AppKit
import AirStatKit

/// The top of the panel while a newer release is out: its version, and the button that
/// installs it. Nothing at all otherwise.
struct UpdateBanner: View {
    let updater: Updater

    var body: some View {
        if let release = updater.available {
            HStack(spacing: Design.Space.l) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, Color(nsColor: .controlAccentColor))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Design.Space.xxs) {
                    Text("Bento Stats \(release.version) is available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Design.Palette.primaryText)
                    Text(updater.failure ?? String(localized: "Version \(updater.currentVersion) is installed."))
                        .font(.system(size: 11))
                        .foregroundStyle(updater.failure == nil
                                         ? Design.Palette.secondaryText : Color(nsColor: .systemOrange))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Design.Space.m)
                action
            }
            .padding(.horizontal, Design.Space.l)
            .padding(.vertical, Design.Space.m + 2)
            .background(RoundedRectangle(cornerRadius: Design.Radius.tile, style: .continuous)
                .fill(BentoGrid.surface))
            // The grid's own inset, so the banner lines up with the cards under it.
            .padding([.horizontal, .top], 12)
        }
    }

    @ViewBuilder
    private var action: some View {
        if updater.activity == .installing {
            HStack(spacing: Design.Space.s) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
        } else if updater.failure != nil {
            // Install has failed once; the release page always works.
            pill(String(localized: "Download"), action: updater.openReleasePage)
        } else {
            pill(String(localized: "Install"), action: updater.install)
        }
    }

    /// A filled capsule rather than `.borderedProminent`, which greys out in the panel:
    /// the panel never becomes the key window, so a prominent button is always drawn
    /// as inactive.
    private func pill(_ title: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Design.Space.l)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(nsColor: .controlAccentColor)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
