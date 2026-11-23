import SwiftUI

/// Draggable playback progress bar.
///
/// While a drag is in flight the local value wins, so the polling loop can't yank the handle
/// out from under the pointer. The committed value is only sent on release.
struct ScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let accent: Color
    /// Disabled when the provider can't seek — the bar still shows progress.
    let isSeekable: Bool
    /// `stacked` puts the times under the rail; `inline` flanks it with them, for the wide
    /// collapsed card where vertical space is the scarce resource.
    var layout: Layout = .stacked
    let onSeek: (TimeInterval) -> Void

    enum Layout { case stacked, inline }

    @State private var dragPosition: TimeInterval?
    @State private var isHovering = false
    @Environment(\.colorScheme) private var scheme

    private var displayed: TimeInterval { dragPosition ?? position }
    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(displayed / duration, 0), 1)
    }
    private var isActive: Bool { isHovering || dragPosition != nil }

    var body: some View {
        Group {
            switch layout {
            case .stacked:
                VStack(spacing: Theme.Metrics.tightSpacing) {
                    rail
                    HStack {
                        Text(formatTime(displayed))
                        Spacer()
                        Text("-" + formatTime(max(0, duration - displayed)))
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            case .inline:
                HStack(spacing: 10) {
                    Text(formatTime(displayed))
                    rail
                    Text("-" + formatTime(max(0, duration - displayed)))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .opacity(duration > 0 ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(formatTime(displayed)) of \(formatTime(duration))")
        .accessibilityAdjustableAction { direction in
            guard isSeekable, duration > 0 else { return }
            let step: TimeInterval = 10
            onSeek(direction == .increment
                   ? min(duration, position + step)
                   : max(0, position - step))
        }
    }

    private var rail: some View {
        GeometryReader { geo in
            let height: CGFloat = isActive ? 7 : 5
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.railBackground(scheme))
                    .overlay {
                        // Reads as a groove cut into the glass rather than a painted line.
                        Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    }
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.85), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * fraction))
                    .shadow(color: accent.opacity(isActive ? 0.5 : 0.25), radius: 6)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .animation(Theme.Motion.control, value: isHovering)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isSeekable, duration > 0 else { return }
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        dragPosition = ratio * duration
                    }
                    .onEnded { _ in
                        guard isSeekable, let target = dragPosition else { return }
                        onSeek(target)
                        // Held until the next poll confirms, to avoid a visible snap-back.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            dragPosition = nil
                        }
                    }
            )
        }
        .frame(height: layout == .inline ? 12 : 14)
        .onHover { isHovering = $0 }
    }
}
