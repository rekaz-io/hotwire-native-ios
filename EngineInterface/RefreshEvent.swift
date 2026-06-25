public enum RefreshEvent: Equatable, Sendable, Codable {
    case completed(RefreshCorrelationID)

    case failed(RefreshCorrelationID, RefreshFailureReason)
}
