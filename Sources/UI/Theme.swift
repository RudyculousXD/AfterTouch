import SwiftUI

/// Shared visual language. Kept in one place so the main window, the menu-bar popover and the
/// Lock Screen panel read as the same product at three different sizes.
///
/// The surfaces are Apple's Liquid Glass on macOS 26 and a hand-built material stack below it,
/// so the app keeps its 14.0 deployment target without the older path looking like an
/// afterthought.
enum Theme {
    enum Metrics {
        static let cornerRadius: CGFloat = 18
        static let artworkCornerRadius: CGFloat = 12
        static let tightSpacing: CGFloat = 6
        static let spacing: CGFloat = 14
        static let looseSpacing: CGFloat = 22
        /// Corner radii for the Lock Screen card in each state. Continuous curvature, and
        /// wide enough that the expanded card reads as the same object grown rather than a
        /// new sheet.
        static let cardCornerRadius: CGFloat = 26
        static let expandedCardCornerRadius: CGFloat = 28
    }

    enum Motion {
        /// Used for artwork and metadata changes — long enough to read as a crossfade,
        /// short enough not to feel sluggish when skipping tracks quickly.
        static let trackChange: Animation = .smooth(duration: 0.42)
        static let control: Animation = .snappy(duration: 0.18)
        static let scrub: Animation = .linear(duration: 0.12)
        /// Collapse ⇄ expand. A spring with a little overshoot so the card feels like it has
        /// mass, damped enough that the text underneath never wobbles.
        static let expand: Animation = .spring(response: 0.48, dampingFraction: 0.82)
        /// Crossfading the two arrangements. Deliberately shorter than `expand`: the old
        /// arrangement should be gone before the new frame settles.
        static let morph: Animation = .easeInOut(duration: 0.22)
    }

    /// Progress and volume rail colours, tuned to stay visible on glass in both appearances.
    static func railBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }
}

/// `mm:ss`, or `h:mm:ss` for anything over an hour.
func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

// MARK: - Liquid Glass

/// A Liquid Glass surface behind arbitrary content.
///
/// On macOS 26 this is the real thing — `glassEffect` samples and refracts what is behind the
/// window. Over the Lock Screen shield there may be nothing to sample, so a tint derived from
/// the artwork and a specular sheen are drawn on top regardless; the card looks deliberate
/// either way instead of relying on a backdrop that may not exist.
struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Metrics.cardCornerRadius
    var tint: Color = .white
    /// Depth of the drop shadow. Cards want one; inline chips generally don't.
    var elevation: CGFloat = 22

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// `glassEffect` is applied *to* the content rather than to a view behind it: used as a
    /// background it frosts the card's own contents instead of what is behind the window.
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint.opacity(0.18)), in: shape)
                .overlay(sheen)
                .shadow(color: .black.opacity(elevation > 0 ? 0.38 : 0),
                        radius: elevation, y: elevation * 0.45)
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(tint.opacity(0.12)))
                }
                .overlay(sheen)
                .clipShape(shape)
                .shadow(color: .black.opacity(elevation > 0 ? 0.38 : 0),
                        radius: elevation, y: elevation * 0.45)
        }
    }

    /// The two things that make glass read as glass: a brighter top edge where light catches
    /// the bevel, and a gloss falling away from it.
    private var sheen: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.14), .white.opacity(0.02), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0.12),
                            .white.opacity(0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .allowsHitTesting(false)
    }
}

extension View {
    /// Liquid Glass card surface. See `LiquidGlassSurface`.
    func liquidGlass(
        cornerRadius: CGFloat = Theme.Metrics.cardCornerRadius,
        tint: Color = .white,
        elevation: CGFloat = 22
    ) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, tint: tint, elevation: elevation))
    }

    func playerGlass(
        style: GlassStyle,
        cornerRadius: CGFloat = Theme.Metrics.cardCornerRadius,
        tint: Color = .white,
        elevation: CGFloat = 22
    ) -> some View {
        modifier(PlayerGlassSurface(style: style, cornerRadius: cornerRadius,
                                    tint: tint, elevation: elevation))
    }
}

private struct PlayerGlassSurface: ViewModifier {
    let style: GlassStyle
    let cornerRadius: CGFloat
    let tint: Color
    let elevation: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder func body(content: Content) -> some View {
        switch style {
        case .liquidGlass:
            content.liquidGlass(cornerRadius: cornerRadius, tint: tint, elevation: elevation)
        case .tintedGlass:
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(tint.opacity(0.30)))
                }
                .overlay {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.13), .clear],
                                              startPoint: .top, endPoint: .bottom))
                        .allowsHitTesting(false)
                }
                .overlay(shape.strokeBorder(.white.opacity(0.26), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.32), radius: elevation, y: elevation * 0.4)
        case .clearOpaque:
            content
                .background(.black.opacity(0.94), in: shape)
                .overlay(shape.strokeBorder(tint.opacity(0.34), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.40), radius: elevation, y: elevation * 0.4)
        }
    }
}

/// A control with no chrome at all: just the glyph, over a generous invisible hit target.
///
/// The Lock Screen card wears these. On glass sitting over arbitrary wallpaper a row of filled
/// circles reads as three chips resting on the card; the bare glyphs read as the card's own
/// controls, which is what every system Now Playing surface does. The colour is left to the
/// caller so a toggle can still show its on-state.
struct PlainControlStyle: ButtonStyle {
    var diameter: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(Theme.Motion.control, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Circular control used for transport buttons. Glass on macOS 26, and a tinted circle below
/// it. Scales down on press for tactility.
struct CircularControlStyle: ButtonStyle {
    var diameter: CGFloat = 38
    var prominent: Bool = false
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background { background(pressed: configuration.isPressed) }
            .foregroundStyle(prominent ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.Motion.control, value: configuration.isPressed)
            .contentShape(Circle())
    }

    @ViewBuilder private func background(pressed: Bool) -> some View {
        if prominent {
            // The play button keeps a solid accent fill — it is the one control that must be
            // unmistakable at a glance from across a room — with a glass rim over it.
            Circle()
                .fill(tint.opacity(pressed ? 0.85 : 1))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: tint.opacity(0.45), radius: pressed ? 6 : 12, y: 3)
        } else if #available(macOS 26.0, *) {
            Circle()
                .fill(.white.opacity(pressed ? 0.16 : 0.04))
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle().fill(.primary.opacity(pressed ? 0.14 : 0.06))
        }
    }
}
