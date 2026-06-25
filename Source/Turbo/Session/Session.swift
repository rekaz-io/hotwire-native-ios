import EngineInterface
import UIKit
import WebKit

/// A Session represents the main interface for managing
/// a Hotwire app in a web view. Each Session manages a single web view
/// so you should create multiple sessions to have multiple web views, for example
/// when using modals or tabs
@MainActor
public class Session: NSObject {
    public weak var delegate: SessionDelegate?

    public let webView: WKWebView
    public var pathConfiguration: PathConfiguration?

    public var navigationPolicy: (any NavigationPolicy)?

    private lazy var bridge = WebViewBridge(webView: webView)
    private var initialized = false
    private var refreshing = false

    private var isShowingStaleContent = false
    private var isSnapshotCacheStale = false

    private let refreshCoordinator = SessionRefreshCoordinator()

    public var engineEventHandler: ((EngineEvent) -> Void)?

    /// Automatically creates a web view with the passed-in configuration
    public convenience init(webViewConfiguration: WKWebViewConfiguration? = nil) {
        self.init(webView: WKWebView(frame: .zero, configuration: webViewConfiguration ?? WKWebViewConfiguration()))
    }

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()
        setup()
    }

    private func setup() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        bridge.delegate = self
        refreshCoordinator.eventHandler = { [weak self] event in
            self?.emit(.refresh(event))
        }
    }

    private func emit(_ event: EngineEvent) {
        guard let engineEventHandler else { return }
        engineEventHandler(event)
    }

    public func invalidate() {
        refreshCoordinator.failPendingRefresh(with: .sessionTornDown)
    }

    // MARK: Visiting

    private var currentVisit: Visit?
    private var topmostVisit: Visit?
    private var previousVisit: Visit?

    /// The topmost visitable is the visitable that has most recently completed a visit
    public var topmostVisitable: Visitable? {
        topmostVisit?.visitable
    }

    /// The active visitable is the visitable that currently owns the web view
    public var activeVisitable: Visitable? {
        activatedVisitable
    }

    public func visit(_ visitable: Visitable, action: VisitAction) {
        visit(visitable, options: VisitOptions(action: action, response: nil))
    }

    public func visit(_ visitable: Visitable, options: VisitOptions? = nil, reload: Bool = false) {
        visitable.visitableDelegate = self

        if reload {
            initialized = false
        }

        let visit = makeVisit(for: visitable, options: options ?? VisitOptions())
        if let currentVisit {
            refreshCoordinator.visitWasCanceled(currentVisit)
        }
        currentVisit?.cancel()
        currentVisit = visit

        if visit.options.action == .restore {
            emit(.restorationOccurred(location: visit.location))
        }

        log("visit", ["location": visit.location, "options": visit.options, "reload": reload])

        visit.delegate = self
        visit.start()
    }

    private func makeVisit(for visitable: Visitable, options: VisitOptions) -> Visit {
        if initialized {
            return JavaScriptVisit(visitable: visitable, options: options, bridge: bridge, restorationIdentifier: restorationIdentifier(for: visitable))
        } else {
            return ColdBootVisit(visitable: visitable, options: options, bridge: bridge)
        }
    }

    public func reload() {
        guard let visitable = topmostVisitable else { return }

        initialized = false
        visit(visitable)
        topmostVisit = currentVisit
    }

    public func clearSnapshotCache() {
        bridge.clearSnapshotCache()
    }

    // MARK: Caching

    /// Clear the snapshot cache the next time the visitable view appears.
    public func markSnapshotCacheAsStale() {
        isSnapshotCacheStale = true
    }

    /// Reload the `Session` the next time the visitable view appears.
    public func markContentAsStale() {
        isShowingStaleContent = true
    }

    // MARK: Refreshing

    public func refresh(correlationID: RefreshCorrelationID) {
        log("refresh", ["correlationID": correlationID.rawValue])

        refreshCoordinator.beginRefresh(correlationID: correlationID)
        performPendingRefreshIfIdle()
    }

    private func performPendingRefreshIfIdle() {
        guard refreshCoordinator.needsRefreshVisit else { return }
        if let currentVisit, currentVisit.state == .started { return }

        guard topmostVisitable != nil else {
            refreshCoordinator.completePendingRefresh()
            return
        }

        markSnapshotCacheAsStale()
        reload()

        if let currentVisit {
            refreshCoordinator.refreshVisitDidStart(currentVisit)
        }
    }

    // MARK: Visitable activation

    private var activatedVisitable: Visitable?

    private func activateVisitable(_ visitable: Visitable) {
        guard !isActivatedVisitable(visitable) else { return }

        deactivateActivatedVisitable()
        visitable.activateVisitableWebView(webView)
        activatedVisitable = visitable
    }

    private func deactivateActivatedVisitable() {
        guard let visitable = activatedVisitable else { return }
        deactivateVisitable(visitable, showScreenshot: true)
    }

    private func deactivateVisitable(_ visitable: Visitable, showScreenshot: Bool = false) {
        guard isActivatedVisitable(visitable) else { return }

        if showScreenshot {
            visitable.updateVisitableScreenshot()
            visitable.showVisitableScreenshot()
        }

        visitable.deactivateVisitableWebView()
        activatedVisitable = nil
    }

    private func isActivatedVisitable(_ visitable: Visitable) -> Bool {
        return visitable === activatedVisitable
    }

    // MARK: Restoration Identifiers

    private var visitableRestorationIdentifiers = NSMapTable<UIViewController, NSString>(keyOptions: NSPointerFunctions.Options.weakMemory, valueOptions: [])

    private func restorationIdentifier(for visitable: Visitable) -> String? {
        return visitableRestorationIdentifiers.object(forKey: visitable.visitableViewController) as String?
    }

    private func storeRestorationIdentifier(_ restorationIdentifier: String, forVisitable visitable: Visitable) {
        visitableRestorationIdentifiers.setObject(restorationIdentifier as NSString, forKey: visitable.visitableViewController)
    }

    // MARK: - Navigation

    private func completeNavigationForCurrentVisit() {
        guard let visit = currentVisit else { return }

        topmostVisit = visit
        performPendingRefreshIfIdle()
    }

    private func dispositionProperties(for location: URL) -> PathProperties {
        (navigationPolicy?.disposition(for: location) ?? .default).asPathProperties()
    }
}

extension Session: VisitDelegate {
    func visitRequestDidStart(_ visit: Visit) {
        emit(.visitRequestStarted(location: visit.location))
        delegate?.sessionDidStartRequest(self)
    }

    func visitRequestDidFinish(_ visit: Visit) {
        emit(.visitRequestFinished(location: visit.location))
        delegate?.sessionDidFinishRequest(self)
    }

    func visit(_ visit: Visit, requestDidFailWithError error: Error) {
        emit(.visitFailed(location: visit.location, reason: EngineVisitFailureReason(error)))
        refreshCoordinator.refreshVisitDidFail(visit)
        delegate?.session(self, didFailRequestForVisitable: visit.visitable, error: error)
        if visit.state == .canceled {
            performPendingRefreshIfIdle()
        }
    }

    func visitDidInitializeWebView(_ visit: Visit) {
        initialized = true
        delegate?.sessionDidLoadWebView(self)
    }

    func visitWillStart(_ visit: Visit) {
        guard !visit.isPageRefresh else { return }

        visit.visitable.showVisitableScreenshot()
        activateVisitable(visit.visitable)
    }

    func visitDidStart(_ visit: Visit) {
        emit(.visitStarted(location: visit.location))
        guard !visit.hasCachedSnapshot else { return }
        guard !visit.isPageRefresh else { return }

        visit.visitable.showVisitableActivityIndicator()
    }

    func visitWillLoadResponse(_ visit: Visit) {
        visit.visitable.updateVisitableScreenshot()
        visit.visitable.showVisitableScreenshot()
    }

    func visitDidRender(_ visit: Visit) {
        emit(.visitRendered(location: visit.location))
        visit.visitable.hideVisitableScreenshot()
        visit.visitable.hideVisitableActivityIndicator()
        visit.visitable.visitableDidRender()
    }

    func visitDidComplete(_ visit: Visit) {
        guard let restorationIdentifier = visit.restorationIdentifier else { return }
        storeRestorationIdentifier(restorationIdentifier, forVisitable: visit.visitable)
    }

    func visitDidFail(_ visit: Visit) {
        visit.visitable.clearVisitableScreenshot()
        visit.visitable.showVisitableScreenshot()
        visit.visitable.hideVisitableActivityIndicator()
    }

    func visitDidFinish(_ visit: Visit) {
        refreshCoordinator.visitDidFinish(visit)

        if refreshing {
            refreshing = false
            visit.visitable.visitableDidRefresh()
        }

        performPendingRefreshIfIdle()
    }

    func visit(_ visit: Visit, didReceiveAuthenticationChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        delegate?.session(self, didReceiveAuthenticationChallenge: challenge, completionHandler: completionHandler)
    }

    func visitDidProposeVisitToLocation(_ location: URL) {
        let properties = dispositionProperties(for: location)
        let proposal = VisitProposal(url: location, options: VisitOptions(), properties: properties)
        delegate?.session(self, didProposeVisit: proposal)
    }
}

extension Session: VisitableDelegate {
    public func visitableViewWillAppear(_ visitable: Visitable) {
        defer {
            // Prevent double-snapshotting for web -> web visits.
            previousVisit = nil
        }

        if (visitable.visitableViewController as? VisitableViewController)?.appearReason == .revealedByPop {
            emit(.revealedByPop(location: visitable.currentVisitableURL))
        }

        guard let topmostVisit, let currentVisit else { return }

        if isSnapshotCacheStale {
            clearSnapshotCache()
            isSnapshotCacheStale = false
        }

        if isShowingStaleContent {
            // Don't reload over an in-flight forward visit.
            if visitable !== currentVisit.visitable {
                reload()
                isShowingStaleContent = false
                return
            }
        }

        // Back swipe gesture canceled.
        if visitable === topmostVisit.visitable && visitable.visitableViewController.isMovingToParent {
            if topmostVisit.state == .completed {
                refreshCoordinator.visitWasCanceled(currentVisit)
                currentVisit.cancel()
                performPendingRefreshIfIdle()
            } else {
                visit(visitable, action: .advance)
            }
            return
        }

        // Navigating forward - complete navigation early.
        if visitable === currentVisit.visitable {
            let currentVisitHasResponse = currentVisit.options.response?.responseHTML != nil
            
            // Form submission redirects can already be completed here.
            if currentVisit.state == .started || (currentVisitHasResponse && currentVisit.state == .completed) {
                completeNavigationForCurrentVisit()
                return
            }
        }

        // Navigating backward from a web view screen to a web view screen.
        if visitable !== topmostVisit.visitable {
            visit(visitable, action: .restore)
            return
        }
        
        if topmostVisitable === activeVisitable {
            return
        }

        // Navigating backward from a native to a web view screen.
        if visitable === previousVisit?.visitable {
            visit(visitable, action: .restore)
        }
    }

    public func visitableViewDidAppear(_ visitable: Visitable) {
        if let currentVisit = currentVisit, visitable === currentVisit.visitable {
            // Appearing after successful navigation
            completeNavigationForCurrentVisit()
            if currentVisit.state != .failed {
                activateVisitable(visitable)
            }
        } else if let topmostVisit = topmostVisit, visitable === topmostVisit.visitable && topmostVisit.state == .completed {
            // Reappearing after canceled navigation
            visit(visitable, action: .restore)
        }
    }

    public func visitableViewWillDisappear(_ visitable: Visitable) {
        previousVisit = topmostVisit
    }

    public func visitableViewDidDisappear(_ visitable: Visitable) {
        previousVisit?.cacheSnapshot()
        deactivateVisitable(visitable)
    }

    public func visitableDidRequestReload(_ visitable: Visitable) {
        guard visitable === topmostVisitable else { return }
        reload()
    }

    public func visitableDidRequestRefresh(_ visitable: Visitable) {
        guard visitable === topmostVisitable else { return }

        refreshing = true
        visitable.visitableWillRefresh()
        reload()
    }
}

extension Session: WebViewDelegate {
    func webView(_ bridge: WebViewBridge, didProposeVisitToLocation location: URL, options: VisitOptions) {
        let properties = dispositionProperties(for: location)
        let proposal = VisitProposal(url: location, options: options, properties: properties)
        delegate?.session(self, didProposeVisit: proposal)
    }

    func webView(_ webView: WebViewBridge, didStartFormSubmissionToLocation location: URL) {
        delegate?.sessionDidStartFormSubmission(self)
    }

    func webView(_ webView: WebViewBridge, didFinishFormSubmissionToLocation location: URL) {
        delegate?.sessionDidFinishFormSubmission(self)
    }

    func webViewDidInvalidatePage(_ bridge: WebViewBridge) {
        guard let visitable = topmostVisitable else { return }

        visitable.updateVisitableScreenshot()
        visitable.showVisitableScreenshot()
        visitable.showVisitableActivityIndicator()
        reload()
    }

    /// Initial page load failed, this will happen when we couldn't find Turbo JS on the page
    func webView(_ webView: WebViewBridge, didFailInitialPageLoadWithError error: Error) {
        guard let currentVisit = currentVisit, !initialized else { return }

        initialized = false
        currentVisit.cancel()
        visitDidFail(currentVisit)
        visit(currentVisit, requestDidFailWithError: error)
    }

    func webView(_ bridge: WebViewBridge, didFailJavaScriptEvaluationWithError error: Error) {
        guard let currentVisit = currentVisit, initialized else { return }

        initialized = false
        currentVisit.cancel()
        visit(currentVisit.visitable)
    }

    /// Called by the Turbo bridge when a visit request fails with a non-HTTP status code,
    /// suggesting it may be the result of a cross-origin redirect visit.
    ///
    /// Determining a cross-origin redirect is not possible in JavaScript using the Fetch API
    /// due to CORS restrictions, so verification is performed on the native side.
    /// If a redirect is detected, a cross-origin redirect visit is proposed; otherwise,
    /// the visit is failed.
    ///
    /// - Parameters:
    ///   - webView: The web view bridge.
    ///   - location: The original visit location requested.
    ///   - identifier: A unique identifier for the visit.
    func webView(_ webView: WebViewBridge, didFailRequestWithNonHttpStatusToLocation location: URL, identifier: String) {
        log("didFailRequestWithNonHttpStatusToLocation",
            ["location": location,
             "visitIdentifier": identifier]
        )

        Task {
            await resolveRedirect(to: location, identifier: identifier)
        }
    }

    func webViewDidFirstPaint(_ bridge: WebViewBridge) {
        guard let location = (currentVisit ?? topmostVisit)?.location else { return }
        emit(.firstPaint(location: location))
    }

    private func resolveRedirect(to location: URL, identifier: String) async {
        do {
            let result = try await RedirectHandler().resolve(location: location)
            switch result {
            case .noRedirect:
                log("resolveRedirect: no redirect",
                    ["location": location,
                     "visitIdentifier": identifier]
                )
                failCurrentVisit(
                    with: TurboError.http(statusCode: 0),
                    visitIdentifier: identifier
                )
            case .sameOriginRedirect(let url):
                // Same-domain redirects are handled by Turbo.
                // Handling them here could lead to an infinite loop.
                log("resolveRedirect: same domain redirect",
                    ["location": location,
                     "redirectLocation": url,
                     "visitIdentifier": identifier]
                )
                failCurrentVisit(
                    with: TurboError.http(statusCode: 0),
                    visitIdentifier: identifier
                )
            case .crossOriginRedirect(let url):
                visitProposedToCrossOriginRedirect(
                    location: location,
                    redirectLocation: url,
                    visitIdentifier: identifier
                )
            }
        } catch {
            failCurrentVisit(
                with: error,
                visitIdentifier: identifier
            )
        }
    }

    @MainActor
    private func failCurrentVisit(with error: Error, visitIdentifier: String) {
        // This is only relevant to `JavaScriptVisit`, as `ColdBootVisit` currently
        // doesn't go through the same flow.
        guard let visit = currentVisit as? JavaScriptVisit,
              visit.identifier == visitIdentifier else { return }

        visit.fail(with: error)
    }

    @MainActor
    private func visitProposedToCrossOriginRedirect(
        location: URL,
        redirectLocation: URL,
        visitIdentifier: String) {
        log("visitProposedToCrossOriginRedirect",
            ["location": location,
             "redirectLocation": redirectLocation,
             "visitIdentifier": visitIdentifier]
        )

        guard let visit = currentVisit as? JavaScriptVisit,
              visit.identifier == visitIdentifier else { return }

        delegate?.session(self, didProposeVisitToCrossOriginRedirect: redirectLocation)
    }
}

extension Session: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let delegate else {
            decisionHandler(.allow)
            return
        }

        let decision = delegate.session(self, decidePolicyFor: navigationAction)
        decisionHandler(.init(decision: decision))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log("webViewWebContentProcessDidTerminate")
        emit(.contentProcessTerminated)
        refreshCoordinator.failPendingRefresh(with: .webProcessTerminated)
        delegate?.sessionWebViewProcessDidTerminate(self)
    }
}

private func log(_ name: String, _ arguments: [String: Any] = [:]) {
    logger.debug("[Session] \(name) \(arguments)")
}

extension WKNavigationActionPolicy {
    public init(decision: WebViewPolicyManager.Decision) {
        switch decision {
        case .allow:
            self = .allow
        case .cancel:
            self = .cancel
        }
    }
}
