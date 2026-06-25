import EngineInterface
import Foundation

@MainActor
final class SessionRefreshCoordinator {
    var eventHandler: ((RefreshEvent) -> Void)?

    private struct PendingRefresh {
        let correlationID: RefreshCorrelationID
        var refreshVisit: Visit?
    }

    private var pendingRefresh: PendingRefresh?

    var needsRefreshVisit: Bool {
        pendingRefresh != nil && pendingRefresh?.refreshVisit == nil
    }

    func beginRefresh(correlationID: RefreshCorrelationID) {
        if let pendingRefresh {
            self.pendingRefresh = nil
            deliver(.failed(pendingRefresh.correlationID, .superseded))
        }
        pendingRefresh = PendingRefresh(correlationID: correlationID, refreshVisit: nil)
    }

    func refreshVisitDidStart(_ visit: Visit) {
        pendingRefresh?.refreshVisit = visit
    }

    func visitWasCanceled(_ visit: Visit) {
        guard pendingRefresh?.refreshVisit === visit else { return }

        pendingRefresh?.refreshVisit = nil
    }

    func visitDidFinish(_ visit: Visit) {
        guard let pendingRefresh, pendingRefresh.refreshVisit === visit else { return }

        self.pendingRefresh = nil
        if visit.state == .completed {
            deliver(.completed(pendingRefresh.correlationID))
        } else {
            deliver(.failed(pendingRefresh.correlationID, .reloadFailed))
        }
    }

    func refreshVisitDidFail(_ visit: Visit) {
        guard let pendingRefresh, pendingRefresh.refreshVisit === visit else { return }

        self.pendingRefresh = nil
        deliver(.failed(pendingRefresh.correlationID, .reloadFailed))
    }

    func completePendingRefresh() {
        guard let pendingRefresh else { return }

        self.pendingRefresh = nil
        deliver(.completed(pendingRefresh.correlationID))
    }

    func failPendingRefresh(with reason: RefreshFailureReason) {
        guard let pendingRefresh else { return }

        self.pendingRefresh = nil
        deliver(.failed(pendingRefresh.correlationID, reason))
    }

    private func deliver(_ event: RefreshEvent) {
        guard let eventHandler else { return }
        eventHandler(event)
    }
}
