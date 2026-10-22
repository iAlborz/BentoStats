import SwiftUI
import AppKit

/// Bento Stats' mark: the icon's gauge, its sweep and needle, in one colour. Drawn by
/// Scripts/make-icon.swift along with the icon.
///
/// Loaded once and marked as a template, which is the whole reason the file on disk is
/// black on transparent: a template image is re-tinted by AppKit for the appearance it
/// is drawn in, so one asset covers light, dark, vibrancy and increased contrast.
/// Colour baked into the artwork would be colour that cannot follow any of them.
public enum Logo {

    /// SwiftPM's generated `Bundle.module` accessor looks beside the main bundle. That
    /// works for a bare development executable, but a signed macOS app has to keep this
    /// bundle in Contents/Resources: a resource beside Contents is left unsealed and
    /// fails strict code-signature verification. Prefer the packaged location without
    /// evaluating the generated accessor, whose missing-bundle path is a fatal error.
    private static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("AirStats_AirStatUI.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    /// The mark as a template image, or nil if the resource is missing — the callers
    /// draw nothing rather than an empty box.
    ///
    /// The App Store build carries it loose in the app's own Resources instead: a bundle
    /// nested there keeps whatever signature it had when Organizer re-signs the app for
    /// distribution, and App Store Connect refuses one not signed for distribution.
    public static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png")
                ?? resources.url(forResource: "Logo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "Bento Stats"
        return image
    }()
}

/// The mark at a given size, tinted by whatever `foregroundStyle` is in effect.
public struct LogoMark: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        if let image = Logo.image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
