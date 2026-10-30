import Combine
import Foundation

enum AudioDeviceEvent: Equatable {
    case outputsChanged
    case defaultOutputChanged
    case volumeChanged(Float)
}

protocol AudioDeviceProvider: AnyObject {
    var outputsPublisher: AnyPublisher<[AudioOutput], Never> { get }
    var volumePublisher: AnyPublisher<Float, Never> { get }
    /// Hardware-level change notifications; consumers typically react by calling `refresh()`.
    var eventsPublisher: AnyPublisher<AudioDeviceEvent, Never> { get }

    func refresh() async
    func setVolume(_ value: Float)
    func setCurrentOutput(id: String)
}

extension AudioDeviceProvider {
    var eventsPublisher: AnyPublisher<AudioDeviceEvent, Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }
}
