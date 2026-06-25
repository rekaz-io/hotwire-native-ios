import EngineInterface
@testable import HotwireNative

final class SessionSpy: Session {
    var visitWasCalled = false
    var visitAction: VisitAction?

    override func visit(_ visitable: any Visitable, action: VisitAction) {
        visitWasCalled = true
        visitAction = action
        super.visit(visitable, action: action)
    }

    var reloadWasCalled = false

    override func reload() {
        reloadWasCalled = true
        super.reload()
    }

    var markSnapshotCacheAsStaleWasCalled = false

    override func markSnapshotCacheAsStale() {
        markSnapshotCacheAsStaleWasCalled = true
        super.markSnapshotCacheAsStale()
    }

    var refreshCorrelationIDs: [RefreshCorrelationID] = []

    override func refresh(correlationID: RefreshCorrelationID) {
        refreshCorrelationIDs.append(correlationID)
        super.refresh(correlationID: correlationID)
    }
}
