import Combine
import Foundation
import ServiceManagement

final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
