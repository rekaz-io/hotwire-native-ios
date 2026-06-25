import Foundation

public enum EngineEvent: Equatable, Sendable, Codable {
    case visitStarted(location: URL)
    case visitRequestStarted(location: URL)
    case visitRequestFinished(location: URL)
    case firstPaint(location: URL)
    case visitRendered(location: URL)
    case revealedByPop(location: URL)
    case restorationOccurred(location: URL)
    case visitFailed(location: URL, reason: EngineVisitFailureReason)
    case contentProcessTerminated
    case refresh(RefreshEvent)
}
