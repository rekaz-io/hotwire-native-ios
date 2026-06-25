import EngineInterface
@testable import HotwireNative
import XCTest

@MainActor
final class RouteDecisionTests: XCTestCase {
    // MARK: NavigationRouteDisposition — Equatable sanity

    func test_navigationRouteDisposition_equatable() {
        XCTAssertEqual(NavigationRouteDisposition.proceed, .proceed)
        XCTAssertEqual(NavigationRouteDisposition.deferToEngine, .deferToEngine)
        XCTAssertNotEqual(NavigationRouteDisposition.proceed, .deferToEngine)
    }

    // MARK: DefaultNavigationPolicy — preserves legacy deferral

    func test_defaultNavigationPolicy_routeDecision_deferToEngine() {
        let policy = DefaultNavigationPolicy()
        let externalURL = URL(string: "https://external.com/page")!
        XCTAssertEqual(policy.routeDecision(for: externalURL), .deferToEngine)
    }

    func test_defaultNavigationPolicy_routeDecision_deferToEngine_forSameHostURL() {
        let policy = DefaultNavigationPolicy()
        let sameHostURL = URL(string: "https://example.com/page")!
        XCTAssertEqual(policy.routeDecision(for: sameHostURL), .deferToEngine)
    }

    // MARK: .proceed — different-host URL reaches the navigator delegate

    @MainActor
    func test_proceedRouteDecision_differentHostURL_reachesNavigatorDelegate() {
        let delegate = ProposalCapturingDelegate()
        let policy = StubRouteDecisionPolicy(routeDecision: .proceed)
        let navigator = Navigator(
            session: Session(webView: Hotwire.config.makeWebView()),
            delegate: delegate,
            configuration: .init(
                name: "Test",
                startLocation: URL(string: "https://my.app.com")!,
                navigationPolicy: policy
            )
        )

        let externalURL = URL(string: "https://external.com/page")!
        navigator.route(externalURL)

        XCTAssertNotNil(delegate.capturedProposal,
                        "delegate.handle(proposal:) must be called when routeDecision is .proceed")
        XCTAssertEqual(delegate.capturedProposal?.url, externalURL)
    }

    // MARK: .deferToEngine — different-host URL intercepted by Safari handler

    @MainActor
    func test_deferToEngineRouteDecision_differentHostURL_doesNotReachNavigatorDelegate() {
        let delegate = ProposalCapturingDelegate()
        let policy = StubRouteDecisionPolicy(routeDecision: .deferToEngine)
        let navigator = Navigator(
            session: Session(webView: Hotwire.config.makeWebView()),
            delegate: delegate,
            configuration: .init(
                name: "Test",
                startLocation: URL(string: "https://my.app.com")!,
                navigationPolicy: policy
            )
        )

        let externalURL = URL(string: "https://external.com/page")!
        navigator.route(externalURL)

        XCTAssertNil(delegate.capturedProposal,
                     "delegate.handle(proposal:) must NOT be called when routeDecision is .deferToEngine and the Safari handler matches")
    }

    // MARK: nil policy — defers to engine (same-host path used to avoid Safari handler side-effects)

    @MainActor
    func test_nilPolicy_sameHostURL_routesThroughRouter() {
        let delegate = ProposalCapturingDelegate()
        let session = Session(webView: Hotwire.config.makeWebView())
        XCTAssertNil(session.navigationPolicy)

        let navigator = Navigator(
            session: session,
            delegate: delegate,
            configuration: .init(
                name: "Test",
                startLocation: URL(string: "https://example.com")!
            )
        )
        navigator.session.navigationPolicy = nil

        let sameHostURL = URL(string: "https://example.com/page")!
        navigator.route(sameHostURL)

        XCTAssertNotNil(delegate.capturedProposal)
    }
}

// MARK: - Test doubles

private struct StubRouteDecisionPolicy: NavigationPolicy {
    let stubbedRouteDecision: NavigationRouteDisposition

    init(routeDecision: NavigationRouteDisposition) {
        self.stubbedRouteDecision = routeDecision
    }

    func disposition(for url: URL) -> NavigationDisposition { .default }
    func routeDecision(for url: URL) -> NavigationRouteDisposition { stubbedRouteDecision }
}

private final class ProposalCapturingDelegate: NavigatorDelegate {
    private(set) var capturedProposal: VisitProposal?

    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        capturedProposal = proposal
        return .reject
    }
}
