import EngineInterface
import Foundation

extension NavigationDisposition {
    func asPathProperties() -> PathProperties {
        var props: PathProperties = [:]
        props[PathPropertyKey.context] = context.rawValue
        props[PathPropertyKey.presentation] = presentation.rawValue
        props[PathPropertyKey.modalStyle] = modalStyle.rawValue
        props[PathPropertyKey.queryStringPresentation] = queryStringPresentation.rawValue
        props[PathPropertyKey.pullToRefreshEnabled] = pullToRefreshEnabled
        props[PathPropertyKey.modalDismissGestureEnabled] = modalDismissGestureEnabled
        props[PathPropertyKey.animated] = animated
        props[PathPropertyKey.historicalLocation] = historicalLocation
        if let viewControllerIdentifier { props[PathPropertyKey.viewController] = viewControllerIdentifier }
        return props
    }

    init(pathProperties: PathProperties) {
        self.init(
            presentation: NavigationPresentation(rawValue: pathProperties.presentation.rawValue) ?? .default,
            context: NavigationContext(rawValue: pathProperties.context.rawValue) ?? .default,
            modalStyle: NavigationModalStyle(rawValue: pathProperties.modalStyle.rawValue) ?? .large,
            queryStringPresentation: NavigationQueryStringPresentation(rawValue: pathProperties.queryStringPresentation.rawValue) ?? .default,
            pullToRefreshEnabled: pathProperties.pullToRefreshEnabled,
            modalDismissGestureEnabled: pathProperties.modalDismissGestureEnabled,
            animated: pathProperties.animated,
            historicalLocation: pathProperties.historicalLocation,
            viewControllerIdentifier: pathProperties[PathPropertyKey.viewController] as? String
        )
    }
}
