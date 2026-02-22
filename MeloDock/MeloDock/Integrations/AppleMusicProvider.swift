import Combine
import Foundation
import AppKit
import MusicKit

@MainActor
final class AppleMusicProvider: MusicProvider {
    let kind: MusicProviderKind = .appleMusic

    private let player = ApplicationMusicPlayer.shared
    private let scriptQueue = DispatchQueue(label: "com.nano.melodock.applemusic.script", qos: .userInitiated)
    private let playbackSubject = CurrentValueSubject<PlaybackState, Never>(
        .unavailable(provider: .appleMusic, message: "Authorize Apple Music in Settings.")
    )
    private let authSubject = CurrentValueSubject<ProviderAuthState, Never>(.unknown)
    private var musicPlayerInfoObserver: NSObjectProtocol?
    private var cachedPlayerInfoTrack: Track?
    private var cachedPlayerInfoStatus: PlaybackStatus = .stopped
    private var artworkCache: [String: URL] = [:]
    private var pendingArtworkLookups = Set<String>()

    var authState: ProviderAuthState { authSubject.value }
    var authStatePublisher: AnyPublisher<ProviderAuthState, Never> { authSubject.eraseToAnyPublisher() }
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { playbackSubject.eraseToAnyPublisher() }

    init() {
        observeDistributedMusicPlayerInfo()
        updateAuthState(with: MusicAuthorization.currentStatus)
    }

    deinit {
        if let musicPlayerInfoObserver {
            DistributedNotificationCenter.default().removeObserver(musicPlayerInfoObserver)
        }
    }

    func authorize() async {
        let status = await MusicAuthorization.request()
        updateAuthState(with: status)

        guard status == .authorized else { return }

        do {
            _ = try await probeAutomationPermission()
            authSubject.send(.authorized)
        } catch {
            if isAutomationDeniedError(error) {
                let message = mapMusicAutomationErrorMessage(error)
                authSubject.send(.unavailable(message))
                playbackSubject.send(.unavailable(provider: .appleMusic, message: message))
                return
            }

            if isNotRunningAutomationError(error) {
                playbackSubject.send(PlaybackState(
                    provider: .appleMusic,
                    status: .stopped,
                    track: nil,
                    message: "Open Music and start playback."
                ))
                return
            }

            let message = mapMusicAutomationErrorMessage(error)
            authSubject.send(.unavailable(message))
            playbackSubject.send(.unavailable(provider: .appleMusic, message: message))
        }
    }

    func refreshNowPlaying() async {
        updateAuthState(with: MusicAuthorization.currentStatus)

        guard isMusicRunning() else {
            playbackSubject.send(PlaybackState(
                provider: .appleMusic,
                status: .stopped,
                track: nil,
                message: "Open Music and start playback."
            ))
            return
        }

        do {
            if let scriptSnapshot = try await queryMusicAppSnapshot() {
                let applicationTrack = mapCurrentTrackFromApplicationPlayer()
                let mergedTrack = mergeTrackCandidates(
                    scriptTrack: scriptSnapshot.track,
                    applicationTrack: applicationTrack,
                    cachedTrack: cachedPlayerInfoTrack
                )
                let stabilizedTrack = stabilizeTrackMetrics(mergedTrack)
                let trackWithArtwork = applyCachedArtwork(to: stabilizedTrack)
                let status = resolvePlaybackStatus(primary: scriptSnapshot.status, track: trackWithArtwork)

                let state = PlaybackState(
                    provider: .appleMusic,
                    status: status,
                    track: trackWithArtwork,
                    message: trackWithArtwork == nil ? "No Apple Music track is active." : nil
                )
                playbackSubject.send(state)
                scheduleArtworkLookupIfNeeded(for: trackWithArtwork, status: status)

                // Hide "Connect" prompt when the app can read Music directly via Automation.
                if authSubject.value != .authorized {
                    authSubject.send(.authorized)
                }
                return
            }
        } catch {
            if isNotRunningAutomationError(error) {
                // A transient AppleEvents race can report "not running" briefly.
                try? await Task.sleep(nanoseconds: 150_000_000)

                if let scriptSnapshot = try? await queryMusicAppSnapshot() {
                    let stabilizedTrack = stabilizeTrackMetrics(scriptSnapshot.track)
                    let trackWithArtwork = applyCachedArtwork(to: stabilizedTrack)
                    let status = resolvePlaybackStatus(primary: scriptSnapshot.status, track: trackWithArtwork)
                    let state = PlaybackState(
                        provider: .appleMusic,
                        status: status,
                        track: trackWithArtwork,
                        message: trackWithArtwork == nil ? "No Apple Music track is active." : nil
                    )
                    playbackSubject.send(state)
                    scheduleArtworkLookupIfNeeded(for: trackWithArtwork, status: status)
                    return
                }

                playbackSubject.send(PlaybackState(
                    provider: .appleMusic,
                    status: .stopped,
                    track: nil,
                    message: "Open Music and start playback."
                ))
                return
            }

            let message = mapMusicAutomationErrorMessage(error)
            playbackSubject.send(.unavailable(provider: .appleMusic, message: message))
            authSubject.send(.unavailable(message))
            return
        }

        let fallbackTrack = mapCurrentTrackFromApplicationPlayer()
        let fallbackStatus = mapPlaybackStatus(player.state.playbackStatus)
        if fallbackTrack != nil || fallbackStatus != .stopped {
            let stabilizedTrack = stabilizeTrackMetrics(fallbackTrack)
            let trackWithArtwork = applyCachedArtwork(to: stabilizedTrack)
            playbackSubject.send(PlaybackState(
                provider: .appleMusic,
                status: fallbackStatus,
                track: trackWithArtwork,
                message: trackWithArtwork == nil ? "No Apple Music track is active." : nil
            ))
            scheduleArtworkLookupIfNeeded(for: trackWithArtwork, status: fallbackStatus)
        } else if cachedPlayerInfoTrack != nil || cachedPlayerInfoStatus != .stopped {
            let stabilizedTrack = stabilizeTrackMetrics(cachedPlayerInfoTrack)
            let trackWithArtwork = applyCachedArtwork(to: stabilizedTrack)
            let status = resolvePlaybackStatus(primary: cachedPlayerInfoStatus, track: trackWithArtwork)
            playbackSubject.send(PlaybackState(
                provider: .appleMusic,
                status: status,
                track: trackWithArtwork,
                message: trackWithArtwork == nil ? "No Apple Music track is active." : nil
            ))
            scheduleArtworkLookupIfNeeded(for: trackWithArtwork, status: status)
        } else {
            playbackSubject.send(PlaybackState(
                provider: .appleMusic,
                status: .stopped,
                track: nil,
                message: "No Apple Music track is active."
            ))
        }
    }

    func togglePlayPause() async {
        _ = await executeMusicAppCommand("playpause")
        await refreshNowPlaying()
    }

    func playNext() async {
        _ = await executeMusicAppCommand("next track")
        await refreshNowPlaying()
    }

    func playPrevious() async {
        _ = await executeMusicAppCommand("previous track")
        await refreshNowPlaying()
    }

    private func updateAuthState(with status: MusicAuthorization.Status) {
        switch status {
        case .authorized:
            authSubject.send(.authorized)
        case .denied, .restricted:
            authSubject.send(.unauthorized)
        case .notDetermined:
            authSubject.send(.unknown)
        @unknown default:
            authSubject.send(.unavailable("Apple Music authorization status is unavailable."))
        }
    }

    private func executeMusicAppCommand(_ command: String) async -> Bool {
        guard isMusicRunning() else { return false }

        let script = """
        tell application id "com.apple.Music" to \(command)
        return true
        """

        do {
            return try await runAppleScriptBoolean(script)
        } catch {
            if isNotRunningAutomationError(error) {
                return false
            }

            playbackSubject.send(.unavailable(provider: .appleMusic, message: mapMusicAutomationErrorMessage(error)))
            return false
        }
    }

    private func mapCurrentTrackFromApplicationPlayer() -> Track? {
        guard let song = player.queue.currentEntry?.item as? Song else { return nil }

        let duration = song.duration ?? 0
        let progress = max(0, player.playbackTime)
        let artworkURL = song.artwork?.url(width: 240, height: 240)
        let title = sanitizeMetadata(song.title)
        guard title.isEmpty == false else { return nil }
        let artist = sanitizeMetadata(song.artistName)

        return Track(
            id: song.id.rawValue,
            title: title,
            artist: artist.isEmpty ? "Unknown Artist" : artist,
            artworkURL: artworkURL,
            tempoBPM: nil,
            duration: duration,
            progress: progress
        )
    }

    private func observeDistributedMusicPlayerInfo() {
        let notificationName = Notification.Name("com.apple.Music.playerInfo")
        musicPlayerInfoObserver = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            Task { @MainActor [weak self] in
                self?.consumeDistributedPlayerInfo(userInfo)
            }
        }
    }

    private func consumeDistributedPlayerInfo(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return }

        if let rawState = userInfo["Player State"] as? String {
            cachedPlayerInfoStatus = mapPlayerInfoState(rawState)
        }

        let title = sanitizeMetadata(userInfo["Name"] as? String ?? "")
        let artist = sanitizeMetadata(userInfo["Artist"] as? String ?? "")
        let durationMS = parseNumeric(userInfo["Total Time"])
        let positionSec = parseNumeric(userInfo["Player Position"])
        let bpmValue = parseNumeric(userInfo["BPM"])

        if title.isEmpty {
            if cachedPlayerInfoStatus == .stopped {
                cachedPlayerInfoTrack = nil
            }
            return
        }

        let idValue: String
        if let idString = userInfo["PersistentID"] as? String {
            idValue = idString
        } else if let idNumber = userInfo["PersistentID"] as? NSNumber {
            idValue = idNumber.stringValue
        } else {
            idValue = "\(title)|\(artist)|\(Int(durationMS))"
        }

        cachedPlayerInfoTrack = Track(
            id: idValue,
            title: title,
            artist: artist.isEmpty ? "Unknown Artist" : artist,
            artworkURL: nil,
            tempoBPM: bpmValue > 0 ? bpmValue : nil,
            duration: max(0, durationMS / 1000.0),
            progress: max(0, positionSec)
        )
    }

    private func mapPlayerInfoState(_ rawState: String) -> PlaybackStatus {
        let normalized = rawState.lowercased()
        if normalized.contains("play") { return .playing }
        if normalized.contains("pause") { return .paused }
        return .stopped
    }

    private func mapPlaybackStatus(_ status: MusicPlayer.PlaybackStatus) -> PlaybackStatus {
        switch status {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return .stopped
        default:
            return .stopped
        }
    }

    private func queryMusicAppSnapshot() async throws -> MusicAppSnapshot? {
        let script = """
        tell application id "com.apple.Music"
            set stateCode to 0
            try
                if (player state is playing) then
                    set stateCode to 1
                else if (player state is paused) then
                    set stateCode to 2
                end if
            end try

            set trackID to ""
            set trackName to ""
            set trackArtist to ""
            set trackDuration to 0
            set trackBPM to 0
            set streamTitle to ""
            try
                set t to current track
                try
                    set trackName to (get «property pnam» of t as string)
                end try
                if trackName is "" then
                    try
                        set trackName to (name of t as string)
                    end try
                end if

                try
                    set trackArtist to (get «property pArt» of t as string)
                end try
                if trackArtist is "" then
                    try
                        set trackArtist to (artist of t as string)
                    end try
                end if

                try
                    set trackDuration to (get «property pDur» of t as real)
                end try
                if trackDuration is 0 then
                    try
                        set trackDuration to (duration of t as real)
                    end try
                end if

                try
                    set trackBPM to (get «property pBPM» of t as real)
                end try
                if trackBPM is 0 then
                    try
                        set trackBPM to (bpm of t as real)
                    end try
                end if

                try
                    set trackID to (database ID of t as string)
                end try
                if trackID is "" then
                    try
                        set trackID to (persistent ID of t as string)
                    end try
                end if
            end try

            set trackPosition to 0
            try
                set trackPosition to (get «property pPos» as real)
            end try
            if trackPosition is 0 then
                try
                    set trackPosition to (player position)
                end try
            end if

            if trackName is "" then
                try
                    set streamTitle to (current stream title as string)
                end try
                if streamTitle is not "" then
                    set trackName to streamTitle
                end if
            end if

            return {stateCode, trackID, trackName, trackArtist, trackDuration, trackPosition, trackBPM}
        end tell
        """

        guard let payload = try await runMusicSnapshotScript(script) else {
            return nil
        }

        let status = mapScriptPlaybackStatus(payload.stateCode)

        let trackIDRaw = sanitizeMetadata(payload.trackID)
        var trackTitle = sanitizeMetadata(payload.trackTitle)
        var trackArtist = sanitizeMetadata(payload.trackArtist)
        let trackDuration = max(0, payload.trackDuration)
        let trackPosition = max(0, payload.trackPosition)

        if trackTitle.isEmpty {
            if let fallback = try? await queryFallbackTrackText() {
                if fallback.title.isEmpty == false {
                    trackTitle = sanitizeMetadata(fallback.title)
                }
                if fallback.artist.isEmpty == false {
                    trackArtist = sanitizeMetadata(fallback.artist)
                }
            }
        }

        guard trackTitle.isEmpty == false else {
            return MusicAppSnapshot(status: status, track: nil)
        }

        let stableID = trackIDRaw.isEmpty ? "\(trackTitle)|\(trackArtist)|\(Int(trackDuration))" : trackIDRaw
        let track = Track(
            id: stableID,
            title: trackTitle,
            artist: trackArtist.isEmpty ? "Unknown Artist" : trackArtist,
            artworkURL: nil,
            tempoBPM: payload.trackBPM > 0 ? payload.trackBPM : nil,
            duration: trackDuration,
            progress: trackPosition
        )

        return MusicAppSnapshot(status: status, track: track)
    }

    private func queryFallbackTrackText() async throws -> ScriptTrackTextPayload? {
        let script = """
        tell application id "com.apple.Music"
            set trackName to ""
            set trackArtist to ""

            try
                set trackName to (name of current track as string)
            end try

            try
                set trackArtist to (artist of current track as string)
            end try

            if trackName is "" then
                try
                    set trackName to (current stream title as string)
                end try
            end if

            return {trackName, trackArtist}
        end tell
        """

        return try await runTrackTextScript(script)
    }

    private func runAppleScriptBoolean(_ source: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            scriptQueue.async {
                do {
                    let descriptor = try Self.executeAppleScriptSync(source)
                    continuation.resume(returning: descriptor?.booleanValue ?? false)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runMusicSnapshotScript(_ source: String) async throws -> ScriptSnapshotPayload? {
        try await withCheckedThrowingContinuation { continuation in
            scriptQueue.async {
                do {
                    guard let descriptor = try Self.executeAppleScriptSync(source), descriptor.numberOfItems >= 7 else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let payload = ScriptSnapshotPayload(
                        stateCode: Self.descriptorInt(descriptor.atIndex(1)),
                        trackID: Self.descriptorString(descriptor.atIndex(2)),
                        trackTitle: Self.descriptorString(descriptor.atIndex(3)),
                        trackArtist: Self.descriptorString(descriptor.atIndex(4)),
                        trackDuration: Self.descriptorDouble(descriptor.atIndex(5)),
                        trackPosition: Self.descriptorDouble(descriptor.atIndex(6)),
                        trackBPM: Self.descriptorDouble(descriptor.atIndex(7))
                    )

                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runTrackTextScript(_ source: String) async throws -> ScriptTrackTextPayload? {
        try await withCheckedThrowingContinuation { continuation in
            scriptQueue.async {
                do {
                    guard let descriptor = try Self.executeAppleScriptSync(source), descriptor.numberOfItems >= 2 else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let payload = ScriptTrackTextPayload(
                        title: Self.descriptorString(descriptor.atIndex(1)),
                        artist: Self.descriptorString(descriptor.atIndex(2))
                    )
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func probeAutomationPermission() async throws -> Bool {
        let script = """
        tell application id "com.apple.Music"
            launch
            get player state
        end tell
        return true
        """
        return try await runAppleScriptBoolean(script)
    }

    nonisolated private static func executeAppleScriptSync(_ source: String) throws -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            throw MusicAutomationError(message: "Cannot initialize AppleScript for Music automation.", code: nil)
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw Self.scriptError(from: errorInfo)
        }

        return result
    }

    nonisolated private static func scriptError(from info: NSDictionary) -> MusicAutomationError {
        let rawCode = info[NSAppleScript.errorNumber]
        let code: Int?
        if let number = rawCode as? NSNumber {
            code = number.intValue
        } else if let intCode = rawCode as? Int {
            code = intCode
        } else if let stringCode = rawCode as? String, let parsed = Int(stringCode) {
            code = parsed
        } else {
            code = nil
        }

        let message = info[NSAppleScript.errorMessage] as? String ?? "Music automation failed."
        return MusicAutomationError(message: message, code: code)
    }

    nonisolated private static func descriptorString(_ descriptor: NSAppleEventDescriptor?) -> String {
        guard let descriptor else { return "" }
        if let value = descriptor.stringValue {
            return normalizeAppleScriptString(value)
        }
        if let coerced = descriptor.coerce(toDescriptorType: typeUnicodeText), let value = coerced.stringValue {
            return normalizeAppleScriptString(value)
        }
        return ""
    }

    nonisolated private static func descriptorDouble(_ descriptor: NSAppleEventDescriptor?) -> Double {
        guard let descriptor else { return 0 }
        let numeric = descriptor.doubleValue
        if numeric != 0 {
            return numeric
        }

        let rawText = descriptorString(descriptor)
        guard rawText.isEmpty == false else { return 0 }
        let sanitized = rawText.replacingOccurrences(of: ",", with: ".")
        return Double(sanitized) ?? 0
    }

    nonisolated private static func descriptorInt(_ descriptor: NSAppleEventDescriptor?) -> Int {
        guard let descriptor else { return 0 }
        let numeric = descriptor.int32Value
        if numeric != 0 {
            return Int(numeric)
        }

        let rawText = descriptorString(descriptor)
        guard rawText.isEmpty == false else { return 0 }
        return Int(rawText) ?? 0
    }

    nonisolated private static func normalizeAppleScriptString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized == "missing value"
            || normalized == "missingvalue"
            || normalized == "(null)"
            || normalized == "<null>"
            || normalized == "nil" {
            return ""
        }
        return trimmed
    }

    private func mapScriptPlaybackStatus(_ stateCode: Int) -> PlaybackStatus {
        switch stateCode {
        case 1:
            return .playing
        case 2:
            return .paused
        default:
            return .stopped
        }
    }

    private func mapMusicAutomationErrorMessage(_ error: Error) -> String {
        if isAutomationDeniedError(error) {
            return "Allow MeloDock to control Music in System Settings > Privacy & Security > Automation."
        }
        if isNotRunningAutomationError(error) {
            return "Open Music and start playback."
        }
        return error.localizedDescription
    }

    private func isAutomationDeniedError(_ error: Error) -> Bool {
        if let automationError = error as? MusicAutomationError,
           automationError.code == -1743 || automationError.code == -1744 || automationError.code == -10004 {
            return true
        }

        let message = normalizedErrorText(error)
        return message.contains("not authorized")
            || message.contains("not permitted")
            || message.contains("automation")
            || message.contains("permission")
    }

    private func isNotRunningAutomationError(_ error: Error) -> Bool {
        if let automationError = error as? MusicAutomationError,
           automationError.code == -600 || automationError.code == -609 {
            return true
        }

        let message = normalizedErrorText(error)
        return message.contains("isn't running")
            || message.contains("is not running")
            || message.contains("isnt running")
            || message.contains("application not running")
            || message.contains("not running")
    }

    private func normalizedErrorText(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        return raw
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
    }

    private func sanitizeMetadata(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        let normalized = trimmed.lowercased()
        if normalized == "missing value"
            || normalized == "missingvalue"
            || normalized == "(null)"
            || normalized == "<null>"
            || normalized == "nil" {
            return ""
        }

        return trimmed
    }

    private func mergeTrackCandidates(scriptTrack: Track?, applicationTrack: Track?, cachedTrack: Track?) -> Track? {
        let base = scriptTrack ?? applicationTrack ?? cachedTrack
        guard let base else { return nil }

        let candidate = applicationTrack ?? cachedTrack
        guard let candidate else { return base }

        if base.artworkURL == nil, let artworkURL = candidate.artworkURL {
            return Track(
                id: base.id,
                title: base.title,
                artist: base.artist,
                artworkURL: artworkURL,
                tempoBPM: base.tempoBPM ?? candidate.tempoBPM,
                duration: max(base.duration, candidate.duration),
                progress: max(base.progress, candidate.progress)
            )
        }

        guard metadataLikelyMatches(base, candidate) else { return base }

        return Track(
            id: base.id,
            title: base.title,
            artist: base.artist,
            artworkURL: base.artworkURL ?? candidate.artworkURL,
            tempoBPM: base.tempoBPM ?? candidate.tempoBPM,
            duration: max(base.duration, candidate.duration),
            progress: max(base.progress, candidate.progress)
        )
    }

    private func metadataLikelyMatches(_ lhs: Track, _ rhs: Track) -> Bool {
        let lhsTitle = sanitizeMetadata(lhs.title).lowercased()
        let rhsTitle = sanitizeMetadata(rhs.title).lowercased()
        if lhsTitle.isEmpty || rhsTitle.isEmpty {
            return lhs.id == rhs.id
        }

        if lhsTitle == rhsTitle {
            return true
        }

        return lhs.id == rhs.id
    }

    private func stabilizeTrackMetrics(_ track: Track?) -> Track? {
        guard let track else { return nil }

        let current = playbackSubject.value.track
        let currentStatus = playbackSubject.value.status

        var duration = track.duration
        var progress = track.progress
        var tempoBPM = track.tempoBPM

        if let current, metadataLikelyMatches(current, track) {
            if duration <= 0 {
                duration = current.duration
            }
            if progress <= 0 && currentStatus == .playing {
                progress = current.progress
            }
            if tempoBPM == nil {
                tempoBPM = current.tempoBPM
            }
        }

        if let cached = cachedPlayerInfoTrack, metadataLikelyMatches(cached, track) {
            if duration <= 0, cached.duration > 0 {
                duration = cached.duration
            }
            if progress <= 0, cached.progress > 0 {
                progress = max(progress, cached.progress)
            }
            if tempoBPM == nil {
                tempoBPM = cached.tempoBPM
            }
        }

        return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkURL: track.artworkURL,
            tempoBPM: tempoBPM,
            duration: duration,
            progress: progress
        )
    }

    private func resolvePlaybackStatus(primary: PlaybackStatus, track: Track?) -> PlaybackStatus {
        if primary == .playing || primary == .paused {
            return primary
        }

        if cachedPlayerInfoStatus == .playing || cachedPlayerInfoStatus == .paused {
            return cachedPlayerInfoStatus
        }

        let playerStatus = mapPlaybackStatus(player.state.playbackStatus)
        if playerStatus == .playing || playerStatus == .paused {
            return playerStatus
        }

        return track == nil ? .stopped : .paused
    }

    private func applyCachedArtwork(to track: Track?) -> Track? {
        guard let track else { return nil }

        if let artworkURL = track.artworkURL {
            artworkCache[artworkCacheKey(for: track)] = artworkURL
            return track
        }

        guard let cachedURL = artworkCache[artworkCacheKey(for: track)] else {
            return track
        }

        return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkURL: cachedURL,
            tempoBPM: track.tempoBPM,
            duration: track.duration,
            progress: track.progress
        )
    }

    private func scheduleArtworkLookupIfNeeded(for track: Track?, status: PlaybackStatus) {
        guard let track else { return }
        guard track.artworkURL == nil else { return }
        guard status == .playing || status == .paused else { return }

        let key = artworkCacheKey(for: track)
        guard key.isEmpty == false else { return }
        guard artworkCache[key] == nil else { return }
        guard pendingArtworkLookups.contains(key) == false else { return }

        pendingArtworkLookups.insert(key)

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let resolvedURL = await self.lookupArtworkURL(title: track.title, artist: track.artist)
            await MainActor.run {
                self.pendingArtworkLookups.remove(key)

                guard let resolvedURL else { return }
                self.artworkCache[key] = resolvedURL

                let current = self.playbackSubject.value
                guard let currentTrack = current.track, self.metadataLikelyMatches(currentTrack, track) else { return }
                guard currentTrack.artworkURL == nil else { return }

                let updatedTrack = Track(
                    id: currentTrack.id,
                    title: currentTrack.title,
                    artist: currentTrack.artist,
                    artworkURL: resolvedURL,
                    tempoBPM: currentTrack.tempoBPM,
                    duration: currentTrack.duration,
                    progress: currentTrack.progress
                )
                self.playbackSubject.send(
                    PlaybackState(
                        provider: current.provider,
                        status: current.status,
                        track: updatedTrack,
                        message: current.message
                    )
                )
            }
        }
    }

    private func lookupArtworkURL(title: String, artist: String) async -> URL? {
        let cleanedTitle = sanitizeMetadata(title)
        let cleanedArtist = sanitizeMetadata(artist)
        guard cleanedTitle.isEmpty == false else { return nil }

        let query = "\(cleanedTitle) \(cleanedArtist)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        guard let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=1&term=\(encodedQuery)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let rawArtworkURL = payload.results.first?.artworkUrl100 else {
                return nil
            }

            let upgradedArtworkURL = rawArtworkURL
                .replacingOccurrences(of: "100x100bb", with: "600x600bb")
                .replacingOccurrences(of: "100x100-75", with: "600x600-75")

            return URL(string: upgradedArtworkURL)
        } catch {
            return nil
        }
    }

    private func artworkCacheKey(for track: Track) -> String {
        let title = sanitizeMetadata(track.title).lowercased()
        let artist = sanitizeMetadata(track.artist).lowercased()
        if title.isEmpty { return "" }
        return "\(title)|\(artist)"
    }

    private func parseNumeric(_ value: Any?) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            return Double(normalized) ?? 0
        }
        return 0
    }

    private func isMusicRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }
}

private struct MusicAppSnapshot {
    let status: PlaybackStatus
    let track: Track?
}

private struct ScriptSnapshotPayload: Sendable {
    let stateCode: Int
    let trackID: String
    let trackTitle: String
    let trackArtist: String
    let trackDuration: Double
    let trackPosition: Double
    let trackBPM: Double
}

private struct ScriptTrackTextPayload: Sendable {
    let title: String
    let artist: String
}

private struct MusicAutomationError: LocalizedError {
    let message: String
    let code: Int?

    var errorDescription: String? { message }
}

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesSearchItem]
}

private struct ITunesSearchItem: Decodable {
    let artworkUrl100: String?
}
