import SwiftUI

/// Previous and next as bare glyphs around a filled accent Play/Pause circle, all with at least 44pt hit targets.
struct PlayerControlsView: View {
    private enum Layout {
        static let hitSize: CGFloat = 44
        static let spacing: CGFloat = 4
        static let skipGlyphSize: CGFloat = 22
        static let playDiameter: CGFloat = 52
        static let playGlyphSize: CGFloat = 24
        /// Extra space either side of the Play circle, on top of `spacing`.
        static let playMargin: CGFloat = 4
        /// The play triangle's visual center sits left of its bounds' center; nudge it right.
        static let playGlyphOpticalOffset: CGFloat = 2
    }

    let isPlaying: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: Layout.spacing) {
            skipButton(systemName: "backward.fill", label: "Previous Track", action: onPrevious)

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Layout.playGlyphSize, weight: .bold))
                    .offset(x: isPlaying ? 0 : Layout.playGlyphOpticalOffset)
                    .frame(width: Layout.playDiameter, height: Layout.playDiameter)
            }
            .buttonStyle(PlayButtonStyle())
            .focusEffectDisabled()
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .padding(.horizontal, Layout.playMargin)

            skipButton(systemName: "forward.fill", label: "Next Track", action: onNext)
        }
    }

    private func skipButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Layout.skipGlyphSize, weight: .medium))
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

/// Accent circle with a black glyph: grows with a soft accent halo on hover and shrinks while pressed.
/// Under Reduce Motion the size stays fixed and only the halo and opacity respond.
private struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlayButtonBody(configuration: configuration)
    }

    private struct PlayButtonBody: View {
        private enum Layout {
            static let haloWidth: CGFloat = 5
            static let focusRingInset: CGFloat = -3
            static let hoverScale: CGFloat = 1.06
            static let pressedScale: CGFloat = 0.94
        }

        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.black)
                .background(Circle().fill(IslandTheme.accent))
                .background(
                    Circle()
                        .fill(IslandTheme.accentHalo)
                        .padding(-Layout.haloWidth)
                        .opacity(isHovering && !configuration.isPressed ? 1 : 0)
                )
                .overlay(
                    Circle()
                        .strokeBorder(IslandTheme.focusRing, lineWidth: 2)
                        .padding(Layout.focusRingInset)
                        .opacity(isFocused ? 1 : 0)
                )
                .contentShape(Circle())
                .scaleEffect(scale)
                .opacity(isEnabled ? (configuration.isPressed && reduceMotion ? 0.8 : 1) : IslandTheme.dimmedOpacity)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var scale: CGFloat {
            if reduceMotion { return 1 }
            if configuration.isPressed { return Layout.pressedScale }
            return isHovering ? Layout.hoverScale : 1
        }
    }
}
