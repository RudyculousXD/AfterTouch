import SwiftUI

/// Previous / play-pause / next, sized and dressed for a given context.
struct TransportControls: View {
    let isPlaying: Bool
    let accent: Color
    var size: Size = .regular
    var style: Style = .circular
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    enum Size {
        case compact, regular, large
        /// The collapsed Lock Screen card, where the transport is the only thing on its row
        /// and can afford to be the largest element on the card after the artwork.
        case card

        var primary: CGFloat {
            switch self { case .compact: 34; case .regular: 46; case .large: 58; case .card: 46 }
        }
        var secondary: CGFloat {
            switch self { case .compact: 26; case .regular: 34; case .large: 42; case .card: 38 }
        }
        var glyph: CGFloat {
            switch self { case .compact: 11; case .regular: 15; case .large: 19; case .card: 19 }
        }
        /// The play button's glyph, always bigger than the skips — and markedly bigger on the
        /// card, where there is no filled circle to mark it as the primary control.
        var primaryGlyph: CGFloat {
            switch self { case .card: glyph + 7; default: glyph + 3 }
        }
        var spacing: CGFloat {
            switch self { case .compact: 10; case .regular: 18; case .large: 24; case .card: 22 }
        }
    }

    enum Style {
        /// Circular glass buttons — the main window and the menu-bar player.
        case circular
        /// Bare glyphs, no button chrome. See `PlainControlStyle`.
        case plain
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            button(
                symbol: "backward.fill",
                glyph: size.glyph,
                diameter: size.secondary,
                label: "Previous track",
                action: onPrevious
            )

            button(
                symbol: isPlaying ? "pause.fill" : "play.fill",
                glyph: size.primaryGlyph,
                diameter: size.primary,
                prominent: true,
                // Keeps the glyph from shifting as it swaps between the two shapes.
                replacesGlyph: true,
                label: isPlaying ? "Pause" : "Play",
                action: onPlayPause
            )
            .keyboardShortcut(.space, modifiers: [])

            button(
                symbol: "forward.fill",
                glyph: size.glyph,
                diameter: size.secondary,
                label: "Next track",
                action: onNext
            )
        }
    }

    @ViewBuilder
    private func button(
        symbol: String,
        glyph: CGFloat,
        diameter: CGFloat,
        prominent: Bool = false,
        replacesGlyph: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let content = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph))
                .contentTransition(replacesGlyph ? .symbolEffect(.replace) : .identity)
        }
        .help(label)
        .accessibilityLabel(label)

        switch style {
        case .circular:
            content.buttonStyle(
                CircularControlStyle(diameter: diameter, prominent: prominent, tint: accent)
            )
        case .plain:
            // Monochrome by design: the reference card tints nothing in the transport row, and
            // an accent-filled play glyph would fight the artwork tint in the card behind it.
            content
                .buttonStyle(PlainControlStyle(diameter: diameter))
                .foregroundStyle(.white)
        }
    }
}
