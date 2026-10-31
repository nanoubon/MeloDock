#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
final class SpectrumWiringTests: XCTestCase {
    private var opened: [URL] = []

    private func makeSettings(status: AnyPublisher<SpectrumStatus, Never>) -> (SettingsViewModel, SettingsStore, UserDefaults, String) {
        let suite = "SpectrumWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        let spotify = SpotifyProvider(settingsStore: store, keychainService: KeychainService())
        let viewModel = SettingsViewModel(
            settingsStore: store,
            launchAtLoginService: LaunchAtLoginService(),
            musicProviders: [:],
            spotifyProvider: spotify,
            proFeatureService: StoreKitProServiceStub(),
            calendarAccess: CalendarService(),
            spectrumStatus: status,
            openURL: { [unowned self] in self.opened.append($0) })
        return (viewModel, store, defaults, suite)
    }

    func testLiveSpectrumDefaultsOffAndPersistsUnderItsKey() {
        let suite = "SpectrumWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.showLiveSpectrum)
        store.showLiveSpectrum = true
        XCTAssertEqual(defaults.object(forKey: "settings.island.liveSpectrum") as? Bool, true)
        XCTAssertTrue(SettingsStore(defaults: defaults).showLiveSpectrum)
    }

    func testSettingsViewModelMirrorsSwitchAndStatus() {
        let status = CurrentValueSubject<SpectrumStatus, Never>(.off)
        let (viewModel, store, defaults, suite) = makeSettings(status: status.eraseToAnyPublisher())
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(viewModel.showLiveSpectrum)
        XCTAssertEqual(viewModel.spectrumStatus, .off)

        viewModel.showLiveSpectrum = true
        XCTAssertTrue(store.showLiveSpectrum)
        status.send(.denied)
        XCTAssertEqual(viewModel.spectrumStatus, .denied)
    }

    func testAudioPrivacyShortcutOpensTheAudioCapturePane() {
        let (viewModel, _, defaults, suite) = makeSettings(status: Just(.off).eraseToAnyPublisher())
        defer { defaults.removePersistentDomain(forName: suite) }
        viewModel.openAudioCapturePrivacySettings()
        XCTAssertEqual(opened.map(\.absoluteString),
                       ["x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"])
    }

    func testCaptionExplainsEveryState() {
        let off = SpectrumStatusText.caption(enabled: false, status: .off)
        XCTAssertTrue(off.contains("never recorded"))
        XCTAssertEqual(SpectrumStatusText.caption(enabled: false, status: .live), off)
        let states: [SpectrumStatus] = [.off, .waiting, .live, .denied, .unsupported]
        let captions = states.map { SpectrumStatusText.caption(enabled: true, status: $0) }
        XCTAssertEqual(Set(captions).count, states.count)
        XCTAssertTrue(SpectrumStatusText.caption(enabled: true, status: .denied).contains("Audio Recording"))
        XCTAssertTrue(SpectrumStatusText.caption(enabled: true, status: .unsupported).contains("14.2"))
    }

    func testTapTargetsTryTheMusicAppThenTheWholeSystem() {
        XCTAssertEqual(SpectrumTapTarget.attempts(for: .spotify),
                       [.process(bundleID: "com.spotify.client"), .global])
        XCTAssertEqual(SpectrumTapTarget.attempts(for: .appleMusic),
                       [.process(bundleID: "com.apple.Music"), .global])
    }

    func testServiceStaysOffWhileEitherConditionIsMissing() {
        // Neither combination below may start a real tap: that would record from the speakers during the test run.
        var statuses: [SpectrumStatus] = []
        var levels: [[Float]?] = []
        let enabled = CurrentValueSubject<Bool, Never>(false)
        let playing = CurrentValueSubject<Bool, Never>(false)
        let service = CoreAudioTapSpectrumService(
            isEnabled: enabled.eraseToAnyPublisher(), isPlaying: playing.eraseToAnyPublisher(),
            provider: Just(.spotify).eraseToAnyPublisher())
        let c = service.statusPublisher.sink { statuses.append($0) }
        let l = service.levelsPublisher.sink { levels.append($0) }
        defer { c.cancel(); l.cancel() }

        playing.send(true)   // playing, switch off
        XCTAssertEqual(statuses, [.off])
        playing.send(false)
        enabled.send(true)   // switch on, nothing playing
        XCTAssertEqual(statuses, [.off])
        XCTAssertTrue(levels.allSatisfy { $0 == nil })
    }
    // Bug 2: a silent start used to tear down the last tap for good and show a false permission error.
    func testSilentStartTriesTheNextTargetThenKeepsListening() {
        XCTAssertEqual(SpectrumTapStep.step(for: .silent, attempt: 0, of: 2), .tryNext)
        XCTAssertEqual(SpectrumTapStep.step(for: .silent, attempt: 1, of: 2), .reportDenied)
        // The same open tap hears the intro end: it publishes again instead of staying denied.
        XCTAssertEqual(SpectrumTapStep.step(for: .heardAudio, attempt: 1, of: 2), .publish)
        XCTAssertEqual(SpectrumTapStep.step(for: .waiting, attempt: 0, of: 2), .wait)
    }

    func testMonitorRecoversAfterASilentVerdict() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var monitor = TapSilenceMonitor(startedAt: t0)
        monitor.record(rms: 0)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(10)), .silent)
        monitor.record(rms: 0.1)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(11)), .heardAudio)
    }

    // Bug 3: an old macOS was reported only once music played; Settings said "Ready" until then.
    func testOldMacOSIsReportedAsSoonAsTheSwitchIsOn() {
        var statuses: [SpectrumStatus] = []
        let enabled = CurrentValueSubject<Bool, Never>(false)
        let service = CoreAudioTapSpectrumService(
            isEnabled: enabled.eraseToAnyPublisher(), isPlaying: Just(false).eraseToAnyPublisher(),
            provider: Just(.spotify).eraseToAnyPublisher(), tapsSupported: false)
        let c = service.statusPublisher.sink { statuses.append($0) }
        defer { c.cancel() }
        XCTAssertEqual(statuses, [.off])
        enabled.send(true)
        XCTAssertEqual(statuses, [.off, .unsupported])
        enabled.send(false)
        XCTAssertEqual(statuses, [.off, .unsupported, .off])
    }
}
#endif
