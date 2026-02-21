import Combine
import Foundation

protocol AudioDeviceProvider: AnyObject {
    var outputsPublisher: AnyPublisher<[AudioOutput], Never> { get }
    var volumePublisher: AnyPublisher<Float, Never> { get }

    func refresh() async
    func setVolume(_ value: Float)
    func setCurrentOutput(id: String)
}
