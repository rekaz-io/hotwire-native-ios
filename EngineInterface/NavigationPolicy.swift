import Foundation

@MainActor
public protocol NavigationPolicy {
    func disposition(for url: URL) -> NavigationDisposition

    func routeDecision(for url: URL) -> NavigationRouteDisposition
}
