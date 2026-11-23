import SwiftUI

struct SensoryOverlayView: View {
    let isBrightness: Bool
    let value: Double
    let labelStyle: SensoryLabelStyle
    let accent: Color
    let glassStyle: GlassStyle

    private var level: CGFloat { CGFloat(min(max(value, 0), 1)) }
    private var percentage: Int { Int((Double(level) * 100).rounded()) }

    private var symbol: String {
        if isBrightness {
            return value > 0.68 ? "sun.max.fill" : value > 0.28 ? "sun.min.fill" : "sun.min"
        }
        return value <= 0 ? "speaker.slash.fill" : value < 0.34 ? "speaker.fill" : value < 0.68 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private var title: String { isBrightness ? "Brightness" : "Volume" }

    var body: some View {
        HStack(spacing: 12) {
            if labelStyle == .icon {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.09), in: Circle())
            } else {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 66, alignment: .leading)
            }

            VStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [accent.opacity(0.76), accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: proxy.size.width * level)
                            .animation(.smooth(duration: 0.22), value: level)
                    }
                    .frame(height: 5)
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 10)

                HStack(spacing: 0) {
                    Text(isBrightness ? "DISPLAY" : "OUTPUT")
                    Spacer(minLength: 4)
                    Text("\(percentage)%")
                        .monospacedDigit()
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white.opacity(0.56))
            }

        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(width: 276, height: 62)
        .playerGlass(style: glassStyle, cornerRadius: 22, tint: accent, elevation: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(percentage) percent")
    }
}
