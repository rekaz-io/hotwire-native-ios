import EngineInterface
@testable import HotwireNative
import XCTest

@MainActor
final class NavigationPolicyTests: XCTestCase {
    // MARK: NavigationDisposition.default

    func test_defaultDisposition_matchesPathPropertyAccessorDefaults() {
        let disposition = NavigationDisposition.default

        XCTAssertEqual(disposition.presentation, .default)
        XCTAssertEqual(disposition.context, .default)
        XCTAssertEqual(disposition.modalStyle, .large)
        XCTAssertEqual(disposition.queryStringPresentation, .default)
        XCTAssertTrue(disposition.pullToRefreshEnabled)
        XCTAssertTrue(disposition.modalDismissGestureEnabled)
        XCTAssertTrue(disposition.animated)
        XCTAssertFalse(disposition.historicalLocation)
        XCTAssertNil(disposition.viewControllerIdentifier)
    }

    // MARK: Adapter round-trip

    func test_dispositionPathPropertiesRoundTrip_preservesNonDefaultFields() {
        let disposition = NavigationDisposition(
            presentation: .replace,
            context: .modal,
            modalStyle: .medium,
            queryStringPresentation: .replace,
            pullToRefreshEnabled: false,
            modalDismissGestureEnabled: false,
            animated: false,
            historicalLocation: true,
            viewControllerIdentifier: "recipes"
        )

        let roundTripped = NavigationDisposition(pathProperties: disposition.asPathProperties())

        XCTAssertEqual(roundTripped, disposition)
    }

    func test_dispositionPathPropertiesRoundTrip_preservesDefault() {
        let disposition = NavigationDisposition.default

        let roundTripped = NavigationDisposition(pathProperties: disposition.asPathProperties())

        XCTAssertEqual(roundTripped, disposition)
    }

    func test_asPathProperties_usesEngineRawValueKeysAndValues() {
        let disposition = NavigationDisposition(
            presentation: .replace,
            context: .modal,
            modalStyle: .pageSheet,
            queryStringPresentation: .replace,
            pullToRefreshEnabled: false,
            modalDismissGestureEnabled: false,
            animated: false,
            historicalLocation: true,
            viewControllerIdentifier: "recipes"
        )

        let props = disposition.asPathProperties()

        XCTAssertEqual(props.presentation, .replace)
        XCTAssertEqual(props.context, .modal)
        XCTAssertEqual(props.modalStyle, .pageSheet)
        XCTAssertEqual(props.queryStringPresentation, .replace)
        XCTAssertFalse(props.pullToRefreshEnabled)
        XCTAssertFalse(props.modalDismissGestureEnabled)
        XCTAssertFalse(props.animated)
        XCTAssertTrue(props.historicalLocation)
        XCTAssertEqual(props.viewController, "recipes")
    }

    // MARK: DefaultNavigationPolicy

    @MainActor
    func test_defaultNavigationPolicy_derivesDispositionFromGlobalPathConfiguration() {
        let originalConfiguration = Hotwire.config.pathConfiguration
        defer { Hotwire.config.pathConfiguration = originalConfiguration }

        let fileURL = Bundle.module.url(
            forResource: "test-modal-styles-configuration",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let pathConfiguration = PathConfiguration(sources: [.file(fileURL)])
        Hotwire.config.pathConfiguration = pathConfiguration

        let policy = DefaultNavigationPolicy()

        let mediumModal = policy.disposition(for: URL(string: "https://example.com/newMedium")!)
        XCTAssertEqual(mediumModal.context, .modal)
        XCTAssertEqual(mediumModal.modalStyle, .medium)
        XCTAssertTrue(mediumModal.modalDismissGestureEnabled)

        let plainModal = policy.disposition(for: URL(string: "https://example.com/new")!)
        XCTAssertEqual(plainModal.context, .modal)
        XCTAssertFalse(plainModal.modalDismissGestureEnabled)

        let unmatched = policy.disposition(for: URL(string: "https://example.com/unmatched")!)
        XCTAssertEqual(unmatched, .default)
    }

    // MARK: Navigator sourcing properties from the injected policy

    @MainActor
    func test_navigatorWithCustomPolicy_routesProposalWithPolicyDisposition() {
        let delegate = ProposalCapturingDelegate()
        let policy = StubNavigationPolicy(
            disposition: NavigationDisposition(presentation: .replace, context: .modal)
        )
        let navigator = Navigator(
            session: Session(webView: Hotwire.config.makeWebView()),
            delegate: delegate,
            configuration: .init(
                name: "Test",
                startLocation: URL(string: "https://example.com")!,
                navigationPolicy: policy
            )
        )

        navigator.route(URL(string: "https://example.com/anything")!)

        let proposal = try! XCTUnwrap(delegate.capturedProposal)
        XCTAssertEqual(proposal.properties.presentation, .replace)
        XCTAssertEqual(proposal.properties.context, .modal)
    }

    @MainActor
    func test_navigatorWithDefaultReturningPolicy_routesProposalWithDefaultProperties() {
        let delegate = ProposalCapturingDelegate()
        let policy = StubNavigationPolicy(disposition: .default)
        let navigator = Navigator(
            session: Session(webView: Hotwire.config.makeWebView()),
            delegate: delegate,
            configuration: .init(
                name: "Test",
                startLocation: URL(string: "https://example.com")!,
                navigationPolicy: policy
            )
        )

        navigator.route(URL(string: "https://example.com/anything")!)

        let proposal = try! XCTUnwrap(delegate.capturedProposal)
        XCTAssertEqual(proposal.properties.presentation, .default)
        XCTAssertEqual(proposal.properties.context, .default)
        XCTAssertEqual(proposal.properties.modalStyle, .large)
    }
}

// MARK: - Test doubles

private struct StubNavigationPolicy: NavigationPolicy {
    let stubbed: NavigationDisposition
    let stubbedRouteDecision: NavigationRouteDisposition
    init(disposition: NavigationDisposition, routeDecision: NavigationRouteDisposition = .deferToEngine) {
        stubbed = disposition
        stubbedRouteDecision = routeDecision
    }
    func disposition(for url: URL) -> NavigationDisposition { stubbed }
    func routeDecision(for url: URL) -> NavigationRouteDisposition { stubbedRouteDecision }
}

private final class ProposalCapturingDelegate: NavigatorDelegate {
    private(set) var capturedProposal: VisitProposal?

    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        capturedProposal = proposal
        return .reject
    }
}
