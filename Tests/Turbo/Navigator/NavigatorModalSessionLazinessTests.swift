@testable import HotwireNative
import WebKit
import XCTest

@MainActor
final class NavigatorModalSessionLazinessTests: XCTestCase {
    override func setUp() {
        navigationController = TestableNavigationController()
        modalNavigationController = TestableNavigationController()

        navigator = Navigator(
            session: session,
            configuration: .init(name: "Test", startLocation: oneURL)
        )
        hierarchyController = NavigationHierarchyController(
            delegate: navigator,
            navigationController: navigationController,
            modalNavigationController: modalNavigationController
        )
        navigator.hierarchyController = hierarchyController

        loadNavigationControllerInWindow()
    }

    func test_freshNavigator_doesNotConstructModalSession() {
        XCTAssertFalse(navigator.hasConstructedModalSession)
    }

    func test_coldBootForwardVisitAndBackNavigation_neverConstructModalSession() {
        navigator.start()
        XCTAssertEqual(navigationController.viewControllers.count, 1)
        XCTAssertFalse(navigator.hasConstructedModalSession)

        navigator.route(twoURL)
        XCTAssertEqual(navigationController.viewControllers.count, 2)
        XCTAssertFalse(navigator.hasConstructedModalSession)

        navigator.route(oneURL)
        XCTAssertEqual(navigationController.viewControllers.count, 1)
        XCTAssertFalse(navigator.hasConstructedModalSession)

        navigator.pop()
        XCTAssertFalse(navigator.hasConstructedModalSession)
    }

    func test_eagerTouchSites_doNotConstructModalSession() {
        navigator.start()

        navigator.reload()
        XCTAssertFalse(navigator.hasConstructedModalSession)

        navigator.webkitUIDelegate = WKUIController(delegate: navigator)
        XCTAssertFalse(navigator.hasConstructedModalSession)
    }

    func test_modalProposal_lazilyConstructsModalSession() {
        navigator.start()
        XCTAssertFalse(navigator.hasConstructedModalSession)

        navigator.route(VisitProposal(path: "/one", context: .modal))

        XCTAssertTrue(navigator.hasConstructedModalSession)
        XCTAssertEqual(modalNavigationController.viewControllers.count, 1)
    }

    // MARK: - Harness

    private let baseURL = URL(string: "https://example.com")!
    private lazy var oneURL = baseURL.appendingPathComponent("/one")
    private lazy var twoURL = baseURL.appendingPathComponent("/two")

    private let session = Session(webView: Hotwire.config.makeWebView())

    private var navigator: Navigator!
    private var hierarchyController: NavigationHierarchyController!
    private var navigationController: TestableNavigationController!
    private var modalNavigationController: TestableNavigationController!

    private let window = UIWindow()

    // Simulate a "real" app so presenting view controllers works under test.
    private func loadNavigationControllerInWindow() {
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        navigationController.loadViewIfNeeded()
    }
}
