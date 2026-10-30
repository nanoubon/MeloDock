import Combine
import Foundation
import IOKit.ps

/// Snapshot of the internal battery / power adapter state.
struct PowerState: Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var hasBattery: Bool

    static let noBattery = PowerState(percent: 0, isCharging: false, isPluggedIn: true, hasBattery: false)
}

/// Pure mapping from power state changes to island transients.
enum PowerEventMapper {
    static let chargingID = "power.charging"
    static let lowBatteryID = "power.low"
    static let lowThresholds = [20, 10]

    static func events(from old: PowerState?, to new: PowerState) -> [IslandTransient] {
        guard new.hasBattery, let old, old.hasBattery else { return [] }
        var result: [IslandTransient] = []

        let startedCharging = (!old.isCharging && new.isCharging) || (!old.isPluggedIn && new.isPluggedIn)
        if startedCharging {
            result.append(IslandTransient(
                id: chargingID, kind: .power,
                payload: .charging(percent: new.percent, isCharging: new.isCharging),
                duration: 3, sticky: false))
        }

        if !new.isCharging,
           lowThresholds.contains(where: { old.percent > $0 && new.percent <= $0 }) {
            result.append(IslandTransient(
                id: lowBatteryID, kind: .power,
                payload: .batteryLow(percent: new.percent),
                duration: 4, sticky: false))
        }
        return result
    }
}

/// Watches IOKit power source changes and publishes `PowerState`.
@MainActor
final class PowerSourceService {
    private let subject: CurrentValueSubject<PowerState, Never>
    private let stateProvider: () -> PowerState
    private var runLoopSource: CFRunLoopSource?

    var statePublisher: AnyPublisher<PowerState, Never> { subject.eraseToAnyPublisher() }

    /// - Parameter startMonitoring: false skips registering the IOKit run loop source (tests).
    init(stateProvider: @escaping () -> PowerState = PowerSourceService.readSystemState,
         startMonitoring: Bool = true) {
        self.stateProvider = stateProvider
        subject = CurrentValueSubject(stateProvider())
        if startMonitoring { start() }
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    /// Re-reads the state and publishes it.
    func refresh() {
        subject.send(stateProvider())
    }

    private func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let service = Unmanaged<PowerSourceService>.fromOpaque(ctx).takeUnretainedValue()
            // Delivered on the main run loop.
            MainActor.assumeIsolated { service.refresh() }
        }, context) else { return }
        let source = unmanaged.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    nonisolated static func readSystemState() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .noBattery
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Swift.min(100, Swift.max(0, Int((Double(current) / Double(max) * 100).rounded()))) : 0
            return PowerState(
                percent: percent,
                isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                hasBattery: true)
        }
        return .noBattery
    }
}
