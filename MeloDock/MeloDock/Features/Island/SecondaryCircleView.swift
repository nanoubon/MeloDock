import SwiftUI

/// The second-ranked activity as a small black circle to the right of the island.
struct SecondaryCircleView: View {
    let activity: IslandActivity
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            glyph
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(for: activity))
    }

    @ViewBuilder
    private var glyph: some View {
        switch activity.detail {
        case let .capture(mic, camera):
            // Camera wins the single slot when both are active.
            CaptureDot(glyph: camera ? .camera : .mic, size: diameter * 0.55)
                .opacity(mic || camera ? 1 : 0)
        case .nowPlaying:
            Image(systemName: "music.note").font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(IslandTheme.textPrimary)
        case .timer:
            Image(systemName: "timer").font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.orange)
        case .calendar:
            Image(systemName: "calendar").font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.red)
        case .network:
            // Selection never gives the network the secondary slot; this only keeps the switch exhaustive.
            Image(systemName: "arrow.up.arrow.down").font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(IslandTheme.textPrimary)
        }
    }

    static func label(for activity: IslandActivity) -> String {
        switch activity.detail {
        case let .capture(mic, camera):
            camera && mic ? "Camera and microphone in use" : camera ? "Camera in use" : "Microphone in use"
        case .nowPlaying: "Now playing"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .network: "Network speed"
        }
    }
}
