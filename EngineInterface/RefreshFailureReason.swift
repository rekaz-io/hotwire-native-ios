public enum RefreshFailureReason: Equatable, Sendable, Codable {
    case superseded
    case sessionTornDown
    case webProcessTerminated
    case reloadFailed
}
