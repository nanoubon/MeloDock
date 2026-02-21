import Foundation
import MusicKit

final class PermissionsService {
    var currentAppleMusicAuthorization: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    func requestAppleMusicAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }
}
