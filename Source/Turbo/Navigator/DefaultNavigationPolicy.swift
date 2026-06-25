import EngineInterface
import Foundation

public struct DefaultNavigationPolicy: NavigationPolicy {
    public init() {}
    public func disposition(for url: URL) -> NavigationDisposition {
        NavigationDisposition(pathProperties: Hotwire.config.pathConfiguration.properties(for: url))
    }

    public func routeDecision(for url: URL) -> NavigationRouteDisposition { .deferToEngine }
}
