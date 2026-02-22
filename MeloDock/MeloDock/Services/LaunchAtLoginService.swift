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
            lastError = friendlyErrorMessage(for: error)
        }

        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let message = nsError.localizedDescription

        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EPERM) {
            return "Launch at Login ถูกบล็อกในโหมด Debug. ฟีเจอร์นี้จะทำงานเมื่อรันแอพที่ signed และอยู่ใน /Applications."
        }

        if message.localizedCaseInsensitiveContains("operation not permitted") {
            return "ไม่สามารถเปิด Launch at Login ได้ในสภาพแวดล้อมปัจจุบัน. โปรดรันแอพแบบ signed จาก /Applications."
        }

        return message
    }
}
