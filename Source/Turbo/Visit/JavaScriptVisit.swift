import Foundation

/// A `JavaScript` managed visit through the Hotwire library.
/// All visits are `JavaScriptVisits` except the initial `ColdBootVisit`
/// or if a `reload()` is issued.
final class JavaScriptVisit: Visit {
    var identifier = "(pending)"
    private let restorationBehavior: RestorationBehavior
    
    init(
        visitable: Visitable,
        options: VisitOptions,
        bridge: WebViewBridge,
        restorationIdentifier: String?,
        restorationBehavior: RestorationBehavior = .normal
    ) {
        self.restorationBehavior = restorationBehavior
        super.init(visitable: visitable, options: options, bridge: bridge)
        self.restorationIdentifier = restorationIdentifier
    }

    override var debugDescription: String {
        "<JavaScriptVisit identifier: \(identifier), state: \(state), location: \(location)>"
    }

    override func startVisit() {
        log("startVisit")
        bridge.visitDelegate = self

        switch restorationBehavior {
        case .normal:
            bridge.visitLocation(location, options: options, restorationIdentifier: restorationIdentifier)
        case .historyPop:
            bridge.restorePoppedLocation(location, restorationIdentifier: restorationIdentifier)
        }
    }

    override func cancelVisit() {
        log("cancelVisit")
        bridge.cancelVisit(withIdentifier: identifier)
        finishRequest()
    }

    override func failVisit() {
        log("failVisit")
        finishRequest()
    }
}

extension JavaScriptVisit {
    enum RestorationBehavior {
        case normal
        case historyPop
    }
}

extension JavaScriptVisit: WebViewVisitDelegate {
    func webView(_ webView: WebViewBridge, didStartVisitWithIdentifier identifier: String, hasCachedSnapshot: Bool, isPageRefresh: Bool) {
        log("didStartVisitWithIdentifier", ["identifier": identifier, "hasCachedSnapshot": hasCachedSnapshot, "isPageRefresh": isPageRefresh])
        self.identifier = identifier
        self.hasCachedSnapshot = hasCachedSnapshot
        self.isPageRefresh = isPageRefresh
        
        delegate?.visitDidStart(self)
    }
    
    func webView(_ webView: WebViewBridge, didStartRequestForVisitWithIdentifier identifier: String, date: Date) {
        guard identifier == self.identifier else { return }
        log("didStartRequestForVisitWithIdentifier", ["identifier": identifier, "date": date])
        startRequest()
    }
    
    func webView(_ webView: WebViewBridge, didCompleteRequestForVisitWithIdentifier identifier: String) {
        guard identifier == self.identifier else { return }
        log("didCompleteRequestForVisitWithIdentifier", ["identifier": identifier])
        
        if hasCachedSnapshot {
            delegate?.visitWillLoadResponse(self)
        }
    }
    
    func webView(_ webView: WebViewBridge, didFailRequestForVisitWithIdentifier identifier: String, statusCode: Int) {
        guard identifier == self.identifier else { return }
        
        log("didFailRequestForVisitWithIdentifier", ["identifier": identifier, "statusCode": statusCode])
        fail(with: TurboError(statusCode: statusCode))
    }
    
    func webView(_ webView: WebViewBridge, didFinishRequestForVisitWithIdentifier identifier: String, date: Date) {
        guard identifier == self.identifier else { return }
        
        log("didFinishRequestForVisitWithIdentifier", ["identifier": identifier, "date": date])
        finishRequest()
    }
    
    func webView(_ webView: WebViewBridge, didRenderForVisitWithIdentifier identifier: String) {
        guard identifier == self.identifier else { return }

        log("didRenderForVisitWithIdentifier", ["identifier": identifier])
        delegate?.visitDidRender(self)
    }
    
    func webView(_ webView: WebViewBridge, didCompleteVisitWithIdentifier identifier: String, restorationIdentifier: String) {
        guard identifier == self.identifier else { return }
        
        log("didCompleteVisitWithIdentifier", ["identifier": identifier, "restorationIdentifier": restorationIdentifier])
        self.restorationIdentifier = restorationIdentifier
        complete()
    }
    
    private func log(_ name: String, _ arguments: [String: Any] = [:]) {
        logger.debug("[JavascriptVisit] \(name) \(self.location.absoluteString), \(arguments)")
    }
}
