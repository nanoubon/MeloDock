import SwiftUI

struct PlayerControlsView: View {
    private enum Theme {
        static let normalFill = Color.white.opacity(0.11)
        static let normalStroke = Color.white.opacity(0.18)
        static let prominentFill = Color.white
        static let prominentIcon = Color.black.opacity(0.92)
        static let normalIcon = Color.white.opacity(0.96)
    }

    let isPlaying: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            controlButton(systemName: "backward.fill", action: onPrevious)
            controlButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                action: onPlayPause,
                prominent: true
            )
            controlButton(systemName: "forward.fill", action: onNext)
        }
    }

    private func controlButton(
        systemName: String,
        action: @escaping () -> Void,
        prominent: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 15 : 13, weight: .semibold))
                .foregroundStyle(prominent ? Theme.prominentIcon : Theme.normalIcon)
                .frame(width: prominent ? 42 : 40, height: prominent ? 42 : 40)
                .background(
                    Circle()
                        .fill(prominent ? Theme.prominentFill : Theme.normalFill)
                )
                .overlay(
                    Circle()
                        .stroke(prominent ? .clear : Theme.normalStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(prominent ? 0.26 : 0.14), radius: prominent ? 5 : 2.6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
