@preconcurrency import Embassy
import EngineInterface
@testable import HotwireNative
import WebKit
import XCTest

private let defaultTimeout: TimeInterval = 10000

@MainActor
class SessionRefreshTests: XCTestCase {
    private let sessionDelegate = TestSessionDelegate()
    private var session: Session!
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private var receivedEvents: [RefreshEvent] = []
    private var onRefreshEvent: ((RefreshEvent) -> Void)?

    @MainActor
    override func setUp() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Hotwire Native iOS Test/1.0"

        session = Session(webViewConfiguration: configuration)
        session.delegate = sessionDelegate
        session.engineEventHandler = { [weak self] event in
            guard case let .refresh(refreshEvent) = event else { return }
            self?.receivedEvents.append(refreshEvent)
            self?.onRefreshEvent?(refreshEvent)
        }

        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer.turboServer(eventLoop: eventLoop)
        try server.start()
        let eventLoop = eventLoop!
        DispatchQueue.global().async { eventLoop.runForever() }
    }

    override func tearDown() {
        session.webView.configuration.userContentController.removeScriptMessageHandler(forName: "turbo")

        server.stopAndWait()
        eventLoop.stop()
    }

    @MainActor
    func test_refresh_withNoInFlightVisit_reloadsAndEmitsCompleted() async throws {
        try await loadInitialPage()

        let correlationID = RefreshCorrelationID(rawValue: "refresh-idle")
        let terminal = expectation(description: "refresh terminal event")
        onRefreshEvent = { _ in terminal.fulfill() }

        sessionDelegate.sessionDidStartRequestCalled = false
        session.refresh(correlationID: correlationID)

        XCTAssertTrue(sessionDelegate.sessionDidStartRequestCalled)

        await fulfillment(of: [terminal], timeout: defaultTimeout)
        XCTAssertEqual(receivedEvents, [.completed(correlationID)])
    }

    @MainActor
    func test_refresh_duringInFlightForwardVisit_defersWithoutCancelingThenCompletes() async throws {
        try await loadInitialPage()

        let second = TestVisitable(url: url("/one"))
        session.visit(second, reload: true)

        let correlationID = RefreshCorrelationID(rawValue: "refresh-deferred")
        let terminal = expectation(description: "refresh terminal event")
        onRefreshEvent = { _ in terminal.fulfill() }
        session.refresh(correlationID: correlationID)

        XCTAssertTrue(receivedEvents.isEmpty)
        XCTAssertFalse(second.visitableDidDeactivateWebViewWasCalled)

        session.visitableViewWillAppear(second)
        session.visitableViewDidAppear(second)

        XCTAssertTrue(receivedEvents.isEmpty)

        await fulfillment(of: [terminal], timeout: defaultTimeout)
        XCTAssertEqual(receivedEvents, [.completed(correlationID)])
        XCTAssertIdentical(session.topmostVisitable, second)
        XCTAssertFalse(second.visitableDidDeactivateWebViewWasCalled)
    }

    @MainActor
    func test_refresh_deferredDuringForwardVisit_executesAtBackSwipeCancelSettlePoint() async throws {
        let first = try await loadInitialPage(BackSwipeCancelVisitable(url: url("/")))

        let second = TestVisitable(url: url("/one"))
        session.visit(second)

        let correlationID = RefreshCorrelationID(rawValue: "refresh-back-swipe")
        let terminal = expectation(description: "refresh terminal event")
        onRefreshEvent = { _ in terminal.fulfill() }
        session.refresh(correlationID: correlationID)

        XCTAssertTrue(receivedEvents.isEmpty)

        // Drive the back-swipe-cancel branch: the topmost completed visitable
        // reappears while reporting `isMovingToParent`. UIKit only sets that flag
        // during a real appearance transition, so `BackSwipeCancelVisitable`
        // overrides it.
        sessionDelegate.sessionDidStartRequestCalled = false
        session.visitableViewWillAppear(first)

        XCTAssertTrue(sessionDelegate.sessionDidStartRequestCalled)

        await fulfillment(of: [terminal], timeout: defaultTimeout)
        XCTAssertEqual(receivedEvents, [.completed(correlationID)])
    }

    @MainActor
    func test_refresh_whenRefreshVisitCanceledByForwardVisit_redefersAndReexecutes() async throws {
        try await loadInitialPage()

        let correlationID = RefreshCorrelationID(rawValue: "refresh-canceled-reexecutes")
        let terminal = expectation(description: "refresh terminal event")
        onRefreshEvent = { _ in terminal.fulfill() }

        sessionDelegate.sessionDidStartRequestCalled = false
        session.refresh(correlationID: correlationID)
        XCTAssertTrue(sessionDelegate.sessionDidStartRequestCalled)

        // A link tap cancels the refresh-initiated visit before it finishes. The
        // refresh must not resolve: it returns to the deferred phase, keeping its
        // terminal-event obligation until this forward visit settles.
        let second = TestVisitable(url: url("/one"))
        session.visit(second, reload: true)
        XCTAssertTrue(receivedEvents.isEmpty)

        session.visitableViewWillAppear(second)
        session.visitableViewDidAppear(second)

        XCTAssertTrue(receivedEvents.isEmpty)

        await fulfillment(of: [terminal], timeout: defaultTimeout)
        XCTAssertEqual(receivedEvents, [.completed(correlationID)])
    }

    @MainActor
    func test_refresh_whileRefreshPending_supersedesPendingRefresh() async throws {
        try await loadInitialPage()

        let second = TestVisitable(url: url("/one"))
        session.visit(second, reload: true)

        let firstID = RefreshCorrelationID(rawValue: "refresh-superseded")
        let secondID = RefreshCorrelationID(rawValue: "refresh-superseding")
        let terminal = expectation(description: "second refresh terminal event")
        onRefreshEvent = { event in
            if case .completed = event { terminal.fulfill() }
        }

        session.refresh(correlationID: firstID)
        session.refresh(correlationID: secondID)

        XCTAssertEqual(receivedEvents, [.failed(firstID, .superseded)])

        session.visitableViewWillAppear(second)
        session.visitableViewDidAppear(second)

        await fulfillment(of: [terminal], timeout: defaultTimeout)
        XCTAssertEqual(receivedEvents, [.failed(firstID, .superseded), .completed(secondID)])
    }

    @MainActor
    func test_refresh_whenWebProcessTerminates_failsPendingRefresh() async throws {
        try await loadInitialPage()

        let second = TestVisitable(url: url("/one"))
        session.visit(second)

        let correlationID = RefreshCorrelationID(rawValue: "refresh-terminated")
        session.refresh(correlationID: correlationID)
        XCTAssertTrue(receivedEvents.isEmpty)

        session.webViewWebContentProcessDidTerminate(session.webView)

        XCTAssertEqual(receivedEvents, [.failed(correlationID, .webProcessTerminated)])
    }

    @MainActor
    func test_refresh_beforeAnyContentRendered_completesImmediately() {
        let correlationID = RefreshCorrelationID(rawValue: "refresh-unrendered")
        session.refresh(correlationID: correlationID)

        XCTAssertEqual(receivedEvents, [.completed(correlationID)])
    }

    @MainActor
    func test_refresh_whenSessionInvalidatedWhilePending_failsAsSessionTornDown() {
        var events: [RefreshEvent] = []
        var tornDownSession: Session? = Session(webViewConfiguration: WKWebViewConfiguration())
        tornDownSession?.engineEventHandler = { event in
            guard case let .refresh(refreshEvent) = event else { return }
            events.append(refreshEvent)
        }

        let visitable = TestVisitable(url: url("/"))
        tornDownSession?.visit(visitable)

        let correlationID = RefreshCorrelationID(rawValue: "refresh-torn-down")
        tornDownSession?.refresh(correlationID: correlationID)
        XCTAssertTrue(events.isEmpty)

        tornDownSession?.invalidate()
        tornDownSession?.webView.configuration.userContentController.removeScriptMessageHandler(forName: "turbo")
        // TestVisitable holds `visitableDelegate` strongly (production
        // VisitableViewController holds it weak), so the test-local
        // visitable would keep the session alive past `= nil`.
        visitable.visitableDelegate = nil
        tornDownSession = nil

        XCTAssertEqual(events, [.failed(correlationID, .sessionTornDown)])
    }

    // MARK: - Helpers

    @MainActor
    @discardableResult
    private func loadInitialPage(_ providedVisitable: TestVisitable? = nil) async throws -> TestVisitable {
        let visitable = providedVisitable ?? TestVisitable(url: url("/"))
        let loaded = expectation(description: "initial page loads")
        sessionDelegate.didChange = { [weak sessionDelegate] in
            sessionDelegate?.didChange = nil
            loaded.fulfill()
        }
        session.visit(visitable)
        await fulfillment(of: [loaded], timeout: defaultTimeout)
        session.visitableViewWillAppear(visitable)
        session.visitableViewDidAppear(visitable)
        return visitable
    }

    private func url(_ path: String) -> URL {
        let baseURL = URL(string: "http://localhost:8080")!
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(relativePath)
    }
}

private final class BackSwipeCancelVisitable: TestVisitable {
    override var isMovingToParent: Bool { true }
}

@MainActor
class SessionRefreshCoordinatorTests: XCTestCase {
    private var coordinator: SessionRefreshCoordinator!
    private var bridge: WebViewBridge!
    private var events: [RefreshEvent] = []

    override func setUp() {
        coordinator = SessionRefreshCoordinator()
        coordinator.eventHandler = { [weak self] event in
            self?.events.append(event)
        }
        bridge = WebViewBridge(webView: WKWebView())
    }

    func test_visitDidFinish_withUnrelatedVisit_doesNotResolveRefresh() {
        let correlationID = RefreshCorrelationID(rawValue: "refresh")
        coordinator.beginRefresh(correlationID: correlationID)
        let refreshVisit = makeVisit()
        coordinator.refreshVisitDidStart(refreshVisit)

        let unrelatedVisit = makeVisit(path: "/one")
        unrelatedVisit.start()
        unrelatedVisit.complete()
        coordinator.visitDidFinish(unrelatedVisit)
        XCTAssertTrue(events.isEmpty)

        refreshVisit.start()
        refreshVisit.complete()
        coordinator.visitDidFinish(refreshVisit)
        XCTAssertEqual(events, [.completed(correlationID)])
    }

    func test_refreshVisitFailure_resolvesExactlyOnce_whenFailureSignalsRace() {
        let correlationID = RefreshCorrelationID(rawValue: "refresh")
        coordinator.beginRefresh(correlationID: correlationID)
        let refreshVisit = makeVisit()
        coordinator.refreshVisitDidStart(refreshVisit)

        refreshVisit.start()
        refreshVisit.fail(with: TurboError.pageLoadFailure)

        coordinator.refreshVisitDidFail(refreshVisit)
        coordinator.failPendingRefresh(with: .webProcessTerminated)
        coordinator.visitDidFinish(refreshVisit)

        XCTAssertEqual(events, [.failed(correlationID, .reloadFailed)])
    }

    func test_visitWasCanceled_returnsRefreshToDeferredPhase() {
        let correlationID = RefreshCorrelationID(rawValue: "refresh")
        coordinator.beginRefresh(correlationID: correlationID)
        let refreshVisit = makeVisit()
        coordinator.refreshVisitDidStart(refreshVisit)
        XCTAssertFalse(coordinator.needsRefreshVisit)

        // Cancellation re-defers the refresh instead of resolving it, so it
        // executes again at the next safe opportunity.
        coordinator.visitWasCanceled(refreshVisit)
        XCTAssertTrue(coordinator.needsRefreshVisit)
        XCTAssertTrue(events.isEmpty)

        coordinator.visitDidFinish(refreshVisit)
        XCTAssertTrue(events.isEmpty)
    }

    private func makeVisit(path: String = "/") -> Visit {
        let visitable = TestVisitable(url: URL(string: "http://localhost:8080\(path)")!)
        return Visit(visitable: visitable, options: VisitOptions(), bridge: bridge)
    }
}
