import SwiftUI

/// Volume rail with a mute toggle.
///
/// The speaker glyph reflects the actual level, and the whole control hides itself when the
/// provider has no volume capability rather than showing a dead slider.
struct VolumeSlider: View {
    let volume: Int
    let isMuted: Bool
    let accent: Color
    let onChange: (Int) -> Void
    let onToggleMute: () -> Void

    @State private var dragVolume: Int?
    @State private var sparkPulse = false
    @Environment(\.colorScheme) private var scheme

    private var displayed: Int { dragVolume ?? (isMuted ? 0 : volume) }

    private var glyph: String {
        if isMuted || displayed == 0 { return "speaker.slash.fill" }
        if displayed < 33 { return "speaker.fill" }
        if displayed < 66 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: Theme.Metrics.spacing) {
            Button(action: onToggleMute) {
                Image(systemName: glyph)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.railBackground(scheme))
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(displayed) / 100)
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            dragVolume = Int((ratio * 100).rounded())
                        }
                        .onEnded { _ in
                            if let target = dragVolume { onChange(target) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                dragVolume = nil
                            }
                        }
                )
                .overlay(alignment: .trailing) {
                    if displayed >= 100 {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .scaleEffect(sparkPulse ? 1.45 : 0.72)
                            .opacity(sparkPulse ? 1 : 0.6)
                            .offset(x: 7, y: -5)
                            .onAppear {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.48)
                                    .repeatCount(2, autoreverses: true)) { sparkPulse = true }
                            }
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(displayed) percent")
        .accessibilityAdjustableAction { direction in
            let step = 5
            onChange(direction == .increment
                     ? min(100, displayed + step)
                     : max(0, displayed - step))
        }
    }
}
