import Combine
import Foundation
import StoreKit

protocol ProFeatureService: AnyObject {
    var isProPublisher: AnyPublisher<Bool, Never> { get }
    func refresh() async
}

final class StoreKitProServiceStub: ProFeatureService {
    private let subject = CurrentValueSubject<Bool, Never>(false)

    var isProPublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    func refresh() async {
        subject.send(false)
    }
}
