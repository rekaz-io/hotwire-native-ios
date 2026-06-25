public enum EngineVisitFailureReason: Equatable, Sendable, Codable {
    case loadFailed(httpStatusCode: Int?)
}
