import SwiftUI

struct MusicSpectrumView: View {
    let isActive: Bool
    let seed: Int
    let progress: TimeInterval
    let tempoBPM: Double

    private enum Layout {
        static let barCount = 14
        static let barWidth: CGFloat = 3
        static let barHeight: CGFloat = 14
        static let spacing: CGFloat = 3
        static let minScale: CGFloat = 0.18
        static let maxScale: CGFloat = 1.0
    }

    var body: some View {
        Group {
            if isActive {
                TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { _ in
                    bars(for: progress, active: true)
                }
            } else {
                bars(for: progress, active: false)
            }
        }
        .frame(height: Layout.barHeight)
        .accessibilityLabel("Music Spectrum")
    }

    private func bars(for time: TimeInterval, active: Bool) -> some View {
        HStack(alignment: .bottom, spacing: Layout.spacing) {
            ForEach(0..<Layout.barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.white.opacity(active ? 0.92 : 0.34))
                    .frame(width: Layout.barWidth, height: Layout.barHeight)
                    .scaleEffect(
                        x: 1,
                        y: active ? scale(for: index, at: time) : 0.22,
                        anchor: .bottom
                    )
            }
        }
        .frame(height: Layout.barHeight, alignment: .bottom)
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
