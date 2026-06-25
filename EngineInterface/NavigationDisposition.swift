import Foundation

public enum NavigationContext: String, Equatable, Sendable, Codable {
    case `default`
    case modal
}

public enum NavigationPresentation: String, Equatable, Sendable, Codable {
    case `default`, pop, replace, refresh
    case clearAll = "clear_all"
    case replaceRoot = "replace_root"
    case none
}

public enum NavigationModalStyle: String, Equatable, Sendable, Codable {
    case medium, large, full
    case pageSheet = "page_sheet"
    case formSheet = "form_sheet"
}

public enum NavigationQueryStringPresentation: String, Equatable, Sendable, Codable {
    case `default`, replace
}

public struct NavigationDisposition: Equatable, Sendable, Codable {
    public var presentation: NavigationPresentation
    public var context: NavigationContext
    public var modalStyle: NavigationModalStyle
    public var queryStringPresentation: NavigationQueryStringPresentation
    public var pullToRefreshEnabled: Bool
    public var modalDismissGestureEnabled: Bool
    public var animated: Bool
    public var historicalLocation: Bool
    public var viewControllerIdentifier: String?

    public init(presentation: NavigationPresentation = .default,
                context: NavigationContext = .default,
                modalStyle: NavigationModalStyle = .large,
                queryStringPresentation: NavigationQueryStringPresentation = .default,
                pullToRefreshEnabled: Bool = true,
                modalDismissGestureEnabled: Bool = true,
                animated: Bool = true,
                historicalLocation: Bool = false,
                viewControllerIdentifier: String? = nil) {
        self.presentation = presentation
        self.context = context
        self.modalStyle = modalStyle
        self.queryStringPresentation = queryStringPresentation
        self.pullToRefreshEnabled = pullToRefreshEnabled
        self.modalDismissGestureEnabled = modalDismissGestureEnabled
        self.animated = animated
        self.historicalLocation = historicalLocation
        self.viewControllerIdentifier = viewControllerIdentifier
    }

    public static let `default` = NavigationDisposition()
}
