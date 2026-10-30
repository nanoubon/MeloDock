import SwiftUI

/// Previous, play/pause and next as bare glyphs with 44pt hit targets.
struct PlayerControlsView: View {
    private enum Layout {
        static let hitSize: CGFloat = 44
        static let spacing: CGFloat = 12
        static let skipGlyphSize: CGFloat = 20
        static let playGlyphSize: CGFloat = 30
    }

    let isPlaying: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: Layout.spacing) {
            controlButton(systemName: "backward.fill", label: "Previous Track",
                          size: Layout.skipGlyphSize, action: onPrevious)
            controlButton(systemName: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play",
                          size: Layout.playGlyphSize, action: onPlayPause)
            controlButton(systemName: "forward.fill", label: "Next Track",
                          size: Layout.skipGlyphSize, action: onNext)
        }
    }

    private func controlButton(
        systemName: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: Layout.hitSize, height: Layout.hitSize)
        }
        .buttonStyle(TransportButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel(label)
    }
}

/// Glyph button: a faint circle on hover, shrinks and fades while pressed, custom focus ring.
private struct TransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TransportButtonBody(configuration: configuration)
    }

    private struct TransportButtonBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(IslandTheme.textPrimary)
                .background(Circle().fill(isHovering ? IslandTheme.buttonHover : .clear))
                .overlay(Circle().strokeBorder(IslandTheme.focusRing, lineWidth: 2).opacity(isFocused ? 1 : 0))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : IslandTheme.dimmedOpacity)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
