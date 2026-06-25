import EngineInterface
import Foundation

extension EngineVisitFailureReason {
    init(_ error: Error) {
        if case let TurboError.http(statusCode) = error {
            self = .loadFailed(httpStatusCode: statusCode)
        } else {
            self = .loadFailed(httpStatusCode: nil)
        }
    }
}
