import SwiftUI

/// One direction of the readout: an arrow and a short rate. A zero rate is dimmed.
struct NetworkSpeedLabel: View {
    let arrow: String
    let bytesPerSecond: Double
    var fontSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 1) {
            Text(arrow)
                .foregroundStyle(IslandTheme.textSecondary)
            Text(NetworkSpeedFormat.short(bytesPerSecond))
                .foregroundStyle(bytesPerSecond < 1 ? IslandTheme.textTertiary : IslandTheme.textPrimary)
        }
        .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

enum NetworkSpeedAccessibility {
    static func label(_ speed: NetworkSpeed) -> String {
        "Download \(NetworkSpeedFormat.spoken(speed.download)), upload \(NetworkSpeedFormat.spoken(speed.upload))"
    }
}

/// Compact ears for the network speed alone: download on the leading ear, upload on the trailing ear.
struct CompactNetworkView: View {
    @ObservedObject var model: NetworkSpeedModel

    var body: some View {
        HStack(spacing: 0) {
            NetworkSpeedLabel(arrow: "↓", bytesPerSecond: model.speed.download)
                .padding(.horizontal, 4)
                .frame(width: IslandShapeMetrics.earWidth)
            Spacer(minLength: 0)
            NetworkSpeedLabel(arrow: "↑", bytesPerSecond: model.speed.upload)
                .padding(.horizontal, 4)
                .frame(width: IslandShapeMetrics.earWidth)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NetworkSpeedAccessibility.label(model.speed))
    }
}

/// The trailing ear while music plays: both rates stacked, download over upload.
struct CompactNetworkStackView: View {
    @ObservedObject var model: NetworkSpeedModel
    var earWidth: CGFloat = IslandShapeMetrics.earWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NetworkSpeedLabel(arrow: "↓", bytesPerSecond: model.speed.download, fontSize: 9)
            NetworkSpeedLabel(arrow: "↑", bytesPerSecond: model.speed.upload, fontSize: 9)
        }
        .padding(.horizontal, 4)
        .frame(width: earWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NetworkSpeedAccessibility.label(model.speed))
    }
}
