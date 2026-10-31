import SwiftUI

/// Color and motion tokens shared by the expanded island and its controls.
enum IslandTheme {
    /// The one accent color (lime, #D4FF3A). Reserved for the artist name, the "Now Playing" eyebrow and its
    /// spectrum, the progress fill, the Play button, the selected tab underline and the compact spectrum.
    static let accent = Color(red: 212 / 255, green: 1, blue: 58 / 255)
    /// Accent at 18%, the halo around the hovered Play button.
    static let accentHalo = accent.opacity(0.18)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.55)
    /// Secondary figures beside primary ones, such as the track duration.
    static let textMuted = Color.white.opacity(0.60)

    static let chipFill = Color.white.opacity(0.10)
    static let chipHover = Color.white.opacity(0.16)
    static let chipPressed = Color.white.opacity(0.20)
    static let buttonHover = Color.white.opacity(0.12)
    static let focusRing = Color.white.opacity(0.60)
    /// Background of a hovered text link (source and output pickers).
    static let linkHover = Color.white.opacity(0.08)

    static let railTrack = Color.white.opacity(0.22)
    static let progressFill = Color.white.opacity(0.95)
    static let volumeFill = Color.white.opacity(0.90)
    /// Track behind the accent progress fill.
    static let progressTrack = Color.white.opacity(0.20)

    /// Opacity of controls that are disabled or waiting on provider authorization.
    static let dimmedOpacity: Double = 0.35

    /// Rail and knob growth on hover or drag.
    static func railAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.8)
    }
}
