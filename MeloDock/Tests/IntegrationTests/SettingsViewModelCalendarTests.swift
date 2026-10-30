#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
private final class FakeCalendarAccess: CalendarAccessProviding {
    let status: CurrentValueSubject<CalendarAuthorizationStatus, Never>
    var grant: Bool
    var requestCount = 0

    init(status: CalendarAuthorizationStatus, grant: Bool = true) {
        self.status = CurrentValueSubject(status)
        self.grant = grant
    }

    var authorizationStatus: CalendarAuthorizationStatus { status.value }
    var authorizationStatusPublisher: AnyPublisher<CalendarAuthorizationStatus, Never> { status.eraseToAnyPublisher() }

    func requestAccess() async -> Bool {
        requestCount += 1
        status.send(grant ? .authorized : .denied)
        return grant
    }
}

@MainActor
final class SettingsViewModelCalendarTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var opened: [URL] = []

    override func setUp() {
        super.setUp()
        suite = "SettingsViewModelCalendarTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        opened = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeViewModel(access: FakeCalendarAccess) -> (SettingsViewModel, SettingsStore) {
        let store = SettingsStore(defaults: defaults)
        let spotify = SpotifyProvider(settingsStore: store, keychainService: KeychainService())
        let viewModel = SettingsViewModel(
            settingsStore: store,
            launchAtLoginService: LaunchAtLoginService(),
            musicProviders: [:],
            spotifyProvider: spotify,
            proFeatureService: StoreKitProServiceStub(),
            calendarAccess: access,
            openURL: { [unowned self] in self.opened.append($0) })
        return (viewModel, store)
    }

    func testIslandSwitchesMirrorAndWriteToTheStore() {
        let (viewModel, store) = makeViewModel(access: FakeCalendarAccess(status: .notDetermined))
        XCTAssertTrue(viewModel.showPower && viewModel.showAudio && viewModel.showCapture && viewModel.showTimer)
        XCTAssertFalse(viewModel.showCalendar)
        viewModel.showPower = false
        viewModel.showAudio = false
        viewModel.showCapture = false
        viewModel.showTimer = false
        XCTAssertFalse(store.showPower)
        XCTAssertFalse(store.showAudio)
        XCTAssertFalse(store.showCapture)
        XCTAssertFalse(store.showTimer)
    }

    func testEnablingCalendarRequestsAccessAndTurnsOnWhenGranted() async {
        let access = FakeCalendarAccess(status: .notDetermined, grant: true)
        let (viewModel, store) = makeViewModel(access: access)
        await viewModel.setCalendarEnabled(true)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertTrue(viewModel.showCalendar)
        XCTAssertTrue(store.showCalendar)
        XCTAssertFalse(viewModel.calendarAccessDenied)
    }

    func testEnablingCalendarRevertsAndShowsNoteWhenDenied() async {
        let access = FakeCalendarAccess(status: .notDetermined, grant: false)
        let (viewModel, store) = makeViewModel(access: access)
        await viewModel.setCalendarEnabled(true)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertFalse(viewModel.showCalendar)
        XCTAssertFalse(store.showCalendar)
        XCTAssertTrue(viewModel.calendarAccessDenied)
    }

    func testAlreadyDeniedDoesNotPromptAgain() async {
        let access = FakeCalendarAccess(status: .denied)
        let (viewModel, store) = makeViewModel(access: access)
        await viewModel.setCalendarEnabled(true)
        XCTAssertEqual(access.requestCount, 0)
        XCTAssertFalse(store.showCalendar)
        XCTAssertTrue(viewModel.calendarAccessDenied)
    }

    func testAlreadyAuthorizedEnablesWithoutPrompt() async {
        let access = FakeCalendarAccess(status: .authorized)
        let (viewModel, store) = makeViewModel(access: access)
        await viewModel.setCalendarEnabled(true)
        XCTAssertEqual(access.requestCount, 0)
        XCTAssertTrue(store.showCalendar)
    }

    func testDisablingClearsFlagAndDeniedNote() async {
        let access = FakeCalendarAccess(status: .denied)
        let (viewModel, store) = makeViewModel(access: access)
        await viewModel.setCalendarEnabled(true)
        await viewModel.setCalendarEnabled(false)
        XCTAssertFalse(store.showCalendar)
        XCTAssertFalse(viewModel.calendarAccessDenied)
    }

    func testRevokingAccessInSystemSettingsTurnsCalendarOff() async {
        let access = FakeCalendarAccess(status: .authorized)
        let (viewModel, store) = makeViewModel(access: access)
        await viewModel.setCalendarEnabled(true)
        access.status.send(.denied)
        XCTAssertFalse(viewModel.showCalendar)
        XCTAssertFalse(store.showCalendar)
        XCTAssertTrue(viewModel.calendarAccessDenied)
    }

    func testOpenCalendarPrivacySettingsUsesPrivacyCalendarsURL() {
        let (viewModel, _) = makeViewModel(access: FakeCalendarAccess(status: .denied))
        viewModel.openCalendarPrivacySettings()
        XCTAssertEqual(opened.map(\.absoluteString),
                       ["x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"])
    }
}
#endif
