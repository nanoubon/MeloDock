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
    /// Re-reads the system permission, which can change behind the app's back (System Settings).
    func refreshAuthorizationStatus()
}

/// What the island source needs on top of access: events in a range and a signal when the store changes.
@MainActor
protocol CalendarEventProviding: CalendarAccessProviding {
    var changesPublisher: AnyPublisher<Void, Never> { get }
    func events(from: Date, to: Date) -> [CalendarEventInfo]
}

/// EventKit shell. Creating it does not prompt; only `requestAccess()` does.
@MainActor
final class CalendarService: CalendarEventProviding {
    /// A CurrentValueSubject (not @Published) so subscribers see the new value when they are told about it.
    private let statusSubject: CurrentValueSubject<CalendarAuthorizationStatus, Never>

    private let store = EKEventStore()

    var authorizationStatus: CalendarAuthorizationStatus { statusSubject.value }

    var authorizationStatusPublisher: AnyPublisher<CalendarAuthorizationStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        // Posted on arbitrary threads; consumers assume the main actor.
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: DispatchQueue.main)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init() {
        statusSubject = CurrentValueSubject(Self.currentStatus())
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        refreshAuthorizationStatus()
        return granted && authorizationStatus == .authorized
    }

    func refreshAuthorizationStatus() {
        let status = Self.currentStatus()
        if status != statusSubject.value { statusSubject.send(status) }
    }

    func events(from: Date, to: Date) -> [CalendarEventInfo] {
        // Read the live system state so a just-granted permission is never mistaken for the old one.
        guard Self.currentStatus() == .authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.isDeclinedByCurrentUser($0) }
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

    private static func isDeclinedByCurrentUser(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func currentStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied // denied, restricted, write-only
        }
    }
}
