import Combine
import EventKit
import Foundation

enum CalendarAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
}

/// What Settings needs: the current permission state and a way to ask for it (never called at launch).
@MainActor
protocol CalendarAccessProviding: AnyObject {
    var authorizationStatus: CalendarAuthorizationStatus { get }
    var authorizationStatusPublisher: AnyPublisher<CalendarAuthorizationStatus, Never> { get }
    func requestAccess() async -> Bool
}

/// What the island source needs on top of access: events in a range and a signal when the store changes.
@MainActor
protocol CalendarEventProviding: CalendarAccessProviding {
    var changesPublisher: AnyPublisher<Void, Never> { get }
    func events(from: Date, to: Date) -> [CalendarEventInfo]
}

/// EventKit shell. Creating it does not prompt; only `requestAccess()` does.
@MainActor
final class CalendarService: ObservableObject, CalendarEventProviding {
    @Published private(set) var authorizationStatus: CalendarAuthorizationStatus

    private let store = EKEventStore()

    var authorizationStatusPublisher: AnyPublisher<CalendarAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init() {
        authorizationStatus = Self.currentStatus()
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorizationStatus = Self.currentStatus()
        return granted && authorizationStatus == .authorized
    }

    func events(from: Date, to: Date) -> [CalendarEventInfo] {
        guard authorizationStatus == .authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .map { event in
                CalendarEventInfo(
                    id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title ?? "Event",
                    start: event.startDate,
                    end: event.endDate,
                    location: event.location,
                    joinURL: CalendarWindow.joinURL(from: [event.location, event.notes, event.url?.absoluteString]))
            }
    }

    private static func currentStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied // denied, restricted, write-only
        }
    }
}
