import SwiftUI

/// Album artwork with a crossfade between tracks and a graceful missing-artwork state.
///
/// The `id` is the track's `changeKey` rather than the artwork itself, so artwork arriving
/// late (Spotify's comes over the network) updates in place instead of re-triggering the
/// transition.
struct ArtworkView: View {
    let image: NSImage?
    let trackKey: String
    var cornerRadius: CGFloat = Theme.Metrics.artworkCornerRadius
    var showsShadow: Bool = true

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.trackChange, value: image)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            // A hairline keeps light artwork from bleeding into a light background.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(showsShadow ? 0.28 : 0),
                radius: showsShadow ? 18 : 0, y: showsShadow ? 8 : 0)
        .accessibilityLabel(image == nil ? "No album artwork" : "Album artwork")
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
        }
    }
}
