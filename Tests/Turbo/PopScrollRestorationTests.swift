@preconcurrency import Embassy
import EngineInterface
@testable import HotwireNative
import WebKit
import XCTest

private let defaultTimeout: TimeInterval = 60

/// Regression tests for deferred pop restoration.
///
/// Unlike `EngineEventStreamTests`, these tests build a real same-document Turbo
/// history (advance visits via pushState) before popping, so the deferred
/// restore visit runs against genuine web-side history state.
@MainActor
final class PopScrollRestorationTests: XCTestCase {
    private let sessionDelegate = TestSessionDelegate()
    private var session: Session!
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private var receivedEvents: [EngineEvent] = []

    @MainActor
    override func setUp() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Hotwire Native iOS Test/1.0"

        session = Session(webViewConfiguration: configuration)
        session.delegate = sessionDelegate
        session.engineEventHandler = { [weak self] event in
            self?.receivedEvents.append(event)
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
    func test_pop_afterSameDocumentPush_restoresPoppedLocationScrollAndSessionState() async throws {
        let root = VisitableViewController(url: url("/"))
        root.visitableDelegate = session
        try await coldBoot(root)

        // Make the page scrollable and scroll down so restoration data exists.
        _ = try await session.webView.evaluateJavaScript(
            "document.body.style.height = '5000px'; window.scrollTo(0, 500); true"
        )
        let scrolled = try await waitForJS("window.pageYOffset > 400")
        XCTAssertTrue(scrolled, "harness: the page must actually scroll before restoration can be tested")

        let detail = VisitableViewController(url: url("/one"))
        detail.visitableDelegate = session
        try await push(detail)

        // Interactive pop back to root, completing the gesture.
        root.appearReason = .revealedByPop
        session.visitableViewWillDisappear(detail)
        session.visitableViewWillAppear(root)
        session.visitableViewDidDisappear(detail)
        session.visitableViewDidAppear(root)

        XCTAssertTrue(
            session.topmostVisitable === root,
            "topmostVisit must advance to the restored visitable after a pop, otherwise refresh()/reload() target the dead popped page and pull-to-refresh is ignored"
        )

        let restored = try await waitForJS(
            "window.location.pathname === '/' && Math.abs(window.pageYOffset - 500) < 30"
        )
        XCTAssertTrue(restored, "web view should be back on the popped location with its scroll position restored")
    }

    @MainActor
    func test_popToRoot_acrossTwoScreens_landsOnRootNotIntermediatePage() async throws {
        let root = VisitableViewController(url: url("/"))
        root.visitableDelegate = session
        try await coldBoot(root)

        let detail = VisitableViewController(url: url("/one"))
        detail.visitableDelegate = session
        try await push(detail)

        let deeper = VisitableViewController(url: url("/two"))
        deeper.visitableDelegate = session
        try await push(deeper)

        // Tab re-tap style popToRoot: two native screens pop at once, a single
        // willAppear/didAppear fires for the root.
        root.appearReason = .revealedByPop
        session.visitableViewWillDisappear(deeper)
        session.visitableViewWillAppear(root)
        session.visitableViewDidDisappear(deeper)
        session.visitableViewDidAppear(root)

        let landed = try await waitForJS("window.location.pathname === '/'")
        XCTAssertTrue(landed, "web view should land on the root location, not an intermediate history entry")
    }

    // MARK: - Helpers

    @MainActor
    private func coldBoot(_ visitable: VisitableViewController) async throws {
        size(visitable)
        let loaded = expectation(description: "initial page loads")
        sessionDelegate.didChange = { [weak sessionDelegate] in
            sessionDelegate?.didChange = nil
            loaded.fulfill()
        }
        session.visit(visitable)
        size(visitable)
        await fulfillment(of: [loaded], timeout: defaultTimeout)
        session.visitableViewWillAppear(visitable)
        session.visitableViewDidAppear(visitable)
        size(visitable)
    }

    /// Forward push in device order: visit -> willAppear (visit in flight) ->
    /// wait for the location to land -> didAppear.
    @MainActor
    private func push(_ visitable: VisitableViewController) async throws {
        size(visitable)
        session.visit(visitable)
        size(visitable)
        session.visitableViewWillAppear(visitable)
        let arrived = try await waitForJS(
            "window.location.pathname === '\(visitable.initialVisitableURL.path)'"
        )
        XCTAssertTrue(arrived, "push to \(visitable.initialVisitableURL.path) did not land")
        session.visitableViewDidAppear(visitable)
    }

    /// The web view is never attached to a window in this harness; give the
    /// hosting view controller a realistic frame so the page has a viewport
    /// and can actually scroll.
    @MainActor
    private func size(_ viewController: UIViewController) {
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
    }

    /// Poll a JS boolean expression until it is true or the timeout elapses.
    @MainActor
    private func waitForJS(_ expression: String, timeout: TimeInterval = 20) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = try? await session.webView.evaluateJavaScript("Boolean(\(expression))") as? Bool, value {
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func url(_ path: String) -> URL {
        let baseURL = URL(string: "http://localhost:8080")!
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(relativePath)
    }
}
