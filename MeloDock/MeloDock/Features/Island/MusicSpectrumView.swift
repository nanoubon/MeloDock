import SwiftUI

struct MusicSpectrumView: View {
    let isActive: Bool
    let seed: Int
    let progress: TimeInterval
    let tempoBPM: Double
    /// Real audio levels, one per band. When present the bars follow them; otherwise the synthetic animation runs.
    var levels: [Float]? = nil
    // Bar geometry; the defaults are the compact ear's look.
    var barCount = 14
    var barWidth: CGFloat = 2.8
    var barHeight: CGFloat = 12
    var barSpacing: CGFloat = 2.4

    private enum Layout {
        static let minScale: CGFloat = 0.18
        static let maxScale: CGFloat = 1.0
    }

    var body: some View {
        Group {
            if let levels, !levels.isEmpty {
                let heights = SpectrumLevels.resample(levels, to: barCount)
                bars(active: true) { Layout.minScale + CGFloat(heights[$0]) * (Layout.maxScale - Layout.minScale) }
                    .animation(.easeOut(duration: 0.08), value: levels)
            } else if isActive {
                TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { _ in
                    bars(active: true) { scale(for: $0, at: progress) }
                }
            } else {
                bars(active: false) { _ in 0.22 }
            }
        }
        .frame(height: barHeight)
        .accessibilityLabel("Music Spectrum")
    }

    private func bars(active: Bool, heightScale: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(barGradient(for: index, active: active))
                    .frame(width: barWidth, height: barHeight)
                    .scaleEffect(
                        x: 1,
                        y: heightScale(index),
                        anchor: .bottom
                    )
            }
        }
        .frame(height: barHeight, alignment: .bottom)
    }

    private func barGradient(for index: Int, active: Bool) -> LinearGradient {
        let ratio = Double(index) / Double(max(barCount - 1, 1))

        if active {
            let startHue = 0.58 - (ratio * 0.14)
            let endHue = startHue - 0.03

            let top = Color(
                hue: startHue,
                saturation: 0.36 + (ratio * 0.20),
                brightness: 0.98,
                opacity: 0.98
            )
            let bottom = Color(
                hue: endHue,
                saturation: 0.48 + (ratio * 0.22),
                brightness: 0.82,
                opacity: 0.92
            )

            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }

        let mutedTop = Color.white.opacity(0.40)
        let mutedBottom = Color.white.opacity(0.24)
        return LinearGradient(colors: [mutedTop, mutedBottom], startPoint: .top, endPoint: .bottom)
    }

    private func scale(for index: Int, at time: TimeInterval) -> CGFloat {
        let beatHz = max(0.9, min(4.0, tempoBPM / 60.0))
        let beatPhase = time * beatHz * .pi * 2.0
        let seedPhase = Double(abs(seed % 257)) / 257.0 * .pi * 2.0
        let barPhase = Double(index) * 0.44

        let beatPulse = pow(max(0, sin(beatPhase + seedPhase)), 1.85)
        let lanePulse = 0.5 + 0.5 * sin((beatPhase * 1.5) + barPhase + seedPhase)
        let barWeight = 0.45 + (0.55 * (0.5 + 0.5 * sin(barPhase * 1.2 + seedPhase * 0.7)))

        let composite = min(max((beatPulse * 0.72 + lanePulse * 0.28) * barWeight, 0), 1)
        let clamped = min(max(composite, 0), 1)
        return Layout.minScale + CGFloat(clamped) * (Layout.maxScale - Layout.minScale)
    }
}
