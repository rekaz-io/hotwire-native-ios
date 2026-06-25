@preconcurrency import Embassy
import EngineInterface
@testable import HotwireNative
import WebKit
import XCTest

private let defaultTimeout: TimeInterval = 10000

/// Fixtures can be re-recorded with `RECORD_ENGINE_FIXTURES=1`.
@MainActor
class EngineEventStreamTests: XCTestCase {
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

    // MARK: - Scenarios

    @MainActor
    func test_coldBoot_emitsVisitStartedThenRendered() async throws {
        try await coldBoot(TestVisitable(url: url("/")))

        try verify(.coldBoot)
    }

    @MainActor
    func test_ordinaryVisit_afterColdBoot_emitsSecondVisitStartedThenRendered() async throws {
        try await coldBoot(TestVisitable(url: url("/")))

        let second = TestVisitable(url: url("/one"))
        let rendered = expectation(description: "second visit renders")
        sessionDelegate.didChange = { [weak sessionDelegate] in
            sessionDelegate?.didChange = nil
            rendered.fulfill()
        }
        session.visit(second, reload: true)
        await fulfillment(of: [rendered], timeout: defaultTimeout)
        // Don't drive the appearance lifecycle here: the visit is already
        // `.completed`, so `visitableViewWillAppear` would fall through to the
        // `.restore` branch and emit a spurious `restorationOccurred`. The
        // restore/pop paths are covered by the dedicated tests.

        try verify(.ordinaryVisit)
    }

    @MainActor
    func test_visitFailed_coldBootToPageWithoutTurboJS_emitsVisitStartedThenVisitFailed() async throws {
        // Missing Turbo JS maps to `.loadFailed(httpStatusCode: nil)`.
        let failed = expectation(description: "visit fails")
        installVisitFailedExpectation(failed)
        session.visit(TestVisitable(url: url("/missing-library")))
        await fulfillment(of: [failed], timeout: defaultTimeout)

        try verify(.visitFailed)
    }

    @MainActor
    func test_processDeath_afterColdBoot_emitsContentProcessTerminated() async throws {
        try await coldBoot(TestVisitable(url: url("/")))

        session.webViewWebContentProcessDidTerminate(session.webView)

        try verify(.processDeath)
    }

    @MainActor
    func test_refreshSuccess_afterColdBoot_emitsRefreshReloadThenCompleted() async throws {
        try await coldBoot(TestVisitable(url: url("/")))

        let correlationID = RefreshCorrelationID(rawValue: "refresh-success")
        let terminal = expectation(description: "refresh terminal event")
        installRefreshTerminalExpectation(terminal)
        session.refresh(correlationID: correlationID)
        await fulfillment(of: [terminal], timeout: defaultTimeout)

        try verify(.refreshSuccess)
    }

    @MainActor
    func test_refreshFailure_whenSuperseded_emitsRefreshFailed() async throws {
        try await coldBoot(TestVisitable(url: url("/")))

        let second = TestVisitable(url: url("/one"))
        session.visit(second, reload: true)

        let firstID = RefreshCorrelationID(rawValue: "refresh-failure-superseded")
        let secondID = RefreshCorrelationID(rawValue: "refresh-failure-superseding")
        session.refresh(correlationID: firstID)
        session.refresh(correlationID: secondID)

        // The recorded fixture ends on a dangling `visitStarted(/one)` with no
        // terminal: that forward visit is intentionally still in flight at
        // assert time (it keeps both refreshes deferred so the supersede path is
        // isolated). The missing terminal is the in-flight visit, not a dropped
        // event.
        try verify(.refreshFailure)
    }

    // MARK: - restorationOccurred

    @MainActor
    func test_restorationOccurred_onRestoreVisit_emitsRestorationOccurred() async throws {
        let first = TestVisitable(url: url("/"))
        try await coldBoot(first)

        let restored = expectation(description: "restorationOccurred emitted")
        let existing = session.engineEventHandler
        session.engineEventHandler = { [weak self] event in
            existing?(event)
            if case .restorationOccurred = event {
                _ = self
                restored.fulfill()
            }
        }

        let second = TestVisitable(url: url("/one"))
        session.visit(second, action: .restore)
        await fulfillment(of: [restored], timeout: defaultTimeout)

        XCTAssertTrue(receivedEvents.contains(.restorationOccurred(location: url("/one"))))
    }

    // MARK: - revealedByPop

    @MainActor
    func test_revealedByPop_whenVisitableViewControllerHasRevealedByPopReason_emitsRevealedByPop() {
        let popVisitable = RevealedByPopVisitable(url: url("/"))
        popVisitable.visitableDelegate = session

        session.visitableViewWillAppear(popVisitable)

        XCTAssertTrue(receivedEvents.contains(.revealedByPop(location: url("/"))))
    }

    @MainActor
    func test_revealedByPop_afterColdBoot_precedesRestorationOccurred() async throws {
        try await coldBoot(TestVisitable(url: url("/")))

        let popVisitable = RevealedByPopVisitable(url: url("/"))
        popVisitable.visitableDelegate = session
        session.visitableViewWillAppear(popVisitable)

        let revealed = try XCTUnwrap(receivedEvents.firstIndex(of: .revealedByPop(location: url("/"))))
        let restored = try XCTUnwrap(receivedEvents.firstIndex(of: .restorationOccurred(location: url("/"))))
        XCTAssertLessThan(revealed, restored, "revealedByPop must precede restorationOccurred on a pop-back")
    }

    // MARK: - Fixture round-trip

    func test_revealedByPopFixture_decodesAndRoundTrips() throws {
        let events = try EngineEventFixtures.load(.revealedByPop)

        let expected: [EngineEvent] = [
            .visitStarted(location: url("/")),
            .visitRendered(location: url("/")),
            .visitStarted(location: url("/one")),
            .visitRendered(location: url("/one")),
            .revealedByPop(location: url("/")),
            .restorationOccurred(location: url("/"))
        ]
        XCTAssertEqual(events, expected)

        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([EngineEvent].self, from: data)
        XCTAssertEqual(decoded, expected)
    }

    // MARK: - Codable round-trip

    func test_engineEvent_roundTripsThroughJSON() throws {
        let events: [EngineEvent] = [
            .visitStarted(location: url("/")),
            .firstPaint(location: url("/")),
            .visitRendered(location: url("/one")),
            .visitRequestStarted(location: url("/")),
            .visitRequestFinished(location: url("/")),
            .visitFailed(location: url("/invalid"), reason: .loadFailed(httpStatusCode: 404)),
            .visitFailed(location: url("/invalid"), reason: .loadFailed(httpStatusCode: nil)),
            .contentProcessTerminated,
            .refresh(.completed(RefreshCorrelationID(rawValue: "ok"))),
            .refresh(.failed(RefreshCorrelationID(rawValue: "bad"), .reloadFailed)),
            .revealedByPop(location: url("/")),
            .restorationOccurred(location: url("/"))
        ]

        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([EngineEvent].self, from: data)

        XCTAssertEqual(decoded, events)
    }

    // MARK: - Helpers

    @MainActor
    private func coldBoot(_ visitable: TestVisitable) async throws {
        let loaded = expectation(description: "initial page loads")
        sessionDelegate.didChange = { [weak sessionDelegate] in
            sessionDelegate?.didChange = nil
            loaded.fulfill()
        }
        session.visit(visitable)
        await fulfillment(of: [loaded], timeout: defaultTimeout)
        session.visitableViewWillAppear(visitable)
        session.visitableViewDidAppear(visitable)
    }

    private func installVisitFailedExpectation(_ expectation: XCTestExpectation) {
        let existing = session.engineEventHandler
        session.engineEventHandler = { [weak self] event in
            existing?(event)
            if case .visitFailed = event {
                _ = self
                expectation.fulfill()
            }
        }
    }

    private func installRefreshTerminalExpectation(_ expectation: XCTestExpectation) {
        let existing = session.engineEventHandler
        session.engineEventHandler = { [weak self] event in
            existing?(event)
            if case .refresh = event {
                _ = self
                expectation.fulfill()
            }
        }
    }

    private func verify(_ scenario: EngineEventFixtures.Scenario) throws {
        if ProcessInfo.processInfo.environment["RECORD_ENGINE_FIXTURES"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = String(data: try encoder.encode(receivedEvents), encoding: .utf8)!
            print("RECORDED_FIXTURE \(scenario.rawValue) BEGIN")
            print(json)
            print("RECORDED_FIXTURE \(scenario.rawValue) END")
        }
        let expected = try EngineEventFixtures.load(scenario)
        XCTAssertEqual(receivedEvents, expected)
    }

    private func url(_ path: String) -> URL {
        let baseURL = URL(string: "http://localhost:8080")!
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(relativePath)
    }
}

private final class RevealedByPopVisitable: VisitableViewController {
    override init(url: URL) {
        super.init(url: url)
        appearReason = .revealedByPop
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
