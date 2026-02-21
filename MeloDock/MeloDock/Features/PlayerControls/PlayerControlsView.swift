import SwiftUI

struct PlayerControlsView: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
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
                .font(.system(size: prominent ? 14 : 12, weight: .semibold))
                .frame(width: prominent ? 34 : 30, height: prominent ? 34 : 30)
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(prominent ? .white.opacity(0.24) : .white.opacity(0.14))
        )
    }
}
