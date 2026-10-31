import Foundation

/// The caption under the live spectrum switch in Settings.
enum SpectrumStatusText {
    static func caption(enabled: Bool, status: SpectrumStatus) -> String {
        guard enabled else {
            return "Moves the bars with the real sound. macOS asks for System Audio Recording the first time; the audio is analyzed live and never recorded."
        }
        switch status {
        case .off: return "Ready. Starts listening when music plays."
        case .waiting: return "Listening for sound…"
        case .live: return "Following the sound of the music app."
        case .denied:
            return "No sound received. Allow MeloDock under Privacy & Security → Audio Recording, then relaunch MeloDock. Until then the bars use the built-in animation."
        case .unsupported: return "Needs macOS 14.2 or later. The bars use the built-in animation."
        }
    }
}
