import SwiftUI

/// Pure description of what a transient notice shows: a leading glyph plus a trailing value.
struct SystemAlertContent: Equatable {
    enum Tone: Equatable { case neutral, positive, warning, critical }
    enum Trailing: Equatable {
        case text(String)
        /// Volume level 0...1.
        case bar(Float)
    }

    let symbol: String
    let tone: Tone
    let trailing: Trailing
    let accessibilityLabel: String

    static func make(from transient: IslandTransient) -> SystemAlertContent {
        switch transient.payload {
        case let .charging(percent, isCharging):
            let value = "\(clampedPercent(percent))%"
            return SystemAlertContent(
                symbol: isCharging ? "bolt.fill" : "powerplug.fill", tone: .positive, trailing: .text(value),
                accessibilityLabel: (isCharging ? "Charging, " : "Power connected, ") + value)
        case let .batteryLow(percent):
            let value = "\(clampedPercent(percent))%"
            return SystemAlertContent(
                symbol: "battery.25percent", tone: percent <= 10 ? .critical : .warning, trailing: .text(value),
                accessibilityLabel: "Battery low, \(value)")
        case let .bluetooth(name, connected):
            return SystemAlertContent(
                symbol: connected ? "headphones" : "headphones.slash", tone: connected ? .positive : .neutral,
                trailing: .text(name),
                accessibilityLabel: "\(name) \(connected ? "connected" : "disconnected")")
        case let .volume(level):
            let value = min(max(level, 0), 1)
            return SystemAlertContent(
                symbol: volumeSymbol(value), tone: .neutral, trailing: .bar(value),
                accessibilityLabel: "Volume \(Int((value * 100).rounded())) percent")
        case let .output(name):
            return SystemAlertContent(
                symbol: "hifispeaker.fill", tone: .neutral, trailing: .text(name),
                accessibilityLabel: "Audio output \(name)")
        case .timerDone:
            return SystemAlertContent(
                symbol: "alarm.fill", tone: .warning, trailing: .text("Done"), accessibilityLabel: "Timer done")
        }
    }

    static func clampedPercent(_ percent: Int) -> Int { min(max(percent, 0), 100) }

    static func volumeSymbol(_ level: Float) -> String {
        switch level {
        case ...0: "speaker.slash.fill"
        case ..<(1.0 / 3): "speaker.wave.1.fill"
        case ..<(2.0 / 3): "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Transient notice laid over the collapsed island's ears: glyph on the leading ear, value on the trailing one.
struct SystemAlertView: View {
    let transient: IslandTransient

    private enum Layout {
        static let barWidth: CGFloat = 40
        static let barHeight: CGFloat = 4
    }

    var body: some View {
        let content = SystemAlertContent.make(from: transient)
        HStack(spacing: 0) {
            Image(systemName: content.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(content.tone))
                .frame(width: IslandShapeMetrics.earWidth)

            Spacer(minLength: 0)

            trailing(content.trailing, tone: content.tone)
                .frame(width: IslandShapeMetrics.earWidth)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    @ViewBuilder
    private func trailing(_ trailing: SystemAlertContent.Trailing, tone: SystemAlertContent.Tone) -> some View {
        switch trailing {
        case let .text(value):
            Text(value)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(IslandTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
        case let .bar(level):
            ZStack(alignment: .leading) {
                Capsule().fill(IslandTheme.railTrack)
                Capsule().fill(IslandTheme.volumeFill)
                    .frame(width: Layout.barWidth * CGFloat(level))
            }
            .frame(width: Layout.barWidth, height: Layout.barHeight)
        }
    }

    private func tint(_ tone: SystemAlertContent.Tone) -> Color {
        switch tone {
        case .neutral: IslandTheme.textPrimary
        case .positive: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
