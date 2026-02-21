import Foundation

enum MusicProviderKind: String, CaseIterable, Codable, Identifiable {
    case appleMusic = "apple_music"
    case spotify = "spotify"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

enum ProviderAuthState: Equatable {
    case unknown
    case unauthorized
    case authorized
    case unavailable(String)
}

enum PlaybackStatus: String, Codable {
    case playing
    case paused
    case stopped
    case unavailable
}

struct PlaybackState: Equatable {
    var provider: MusicProviderKind
    var status: PlaybackStatus
    var track: Track?
    var message: String?

    var isPlaying: Bool { status == .playing }

    static func unavailable(provider: MusicProviderKind, message: String) -> PlaybackState {
        PlaybackState(provider: provider, status: .unavailable, track: nil, message: message)
    }
}
