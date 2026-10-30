import Foundation

struct AudioOutput: Identifiable, Equatable {
    let id: String
    let name: String
    let isCurrent: Bool
    var isBluetooth: Bool = false
}
