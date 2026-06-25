public extension PathProperties {
    var context: Navigation.Context {
        guard let rawValue = self[PathPropertyKey.context] as? String,
              let context = Navigation.Context(rawValue: rawValue) else {
            return .default
        }

        return context
    }

    var presentation: Navigation.Presentation {
        guard let rawValue = self[PathPropertyKey.presentation] as? String,
              let presentation = Navigation.Presentation(rawValue: rawValue) else {
            return .default
        }

        return presentation
    }

    var modalStyle: Navigation.ModalStyle {
        guard let rawValue = self[PathPropertyKey.modalStyle] as? String,
              let modalStyle = Navigation.ModalStyle(rawValue: rawValue) else {
            return .large
        }

        return modalStyle
    }

    var pullToRefreshEnabled: Bool {
        self[PathPropertyKey.pullToRefreshEnabled] as? Bool ?? true
    }

    var modalDismissGestureEnabled: Bool {
        self[PathPropertyKey.modalDismissGestureEnabled] as? Bool ?? true
    }

    /// Used to identify a custom native view controller if provided in the path configuration properties of a given pattern.
    ///
    /// For example, given the following configuration file:
    ///
    /// ```json
    /// {
    ///   "rules": [
    ///     {
    ///       "patterns": [
    ///         "/recipes/*"
    ///       ],
    ///       "properties": {
    ///         "view_controller": "recipes",
    ///       }
    ///     }
    ///  ]
    /// }
    /// ```
    ///
    /// A VisitProposal to `https://example.com/recipes/` will have
    /// ```swift
    /// proposal.viewController == "recipes"
    /// ```
    ///
    /// - Important: A default value is provided in case the view controller property is missing from the configuration file. This will route the default `VisitableViewController`.
    /// - Note: A `ViewController` must conform to `PathConfigurationIdentifiable` to couple the identifier with a view controlelr.
    var viewController: String {
        guard let viewController = self[PathPropertyKey.viewController] as? String else {
            return VisitableViewController.pathConfigurationIdentifier
        }

        return viewController
    }

    /// Allows the proposal to change the animation status when pushing, popping or presenting.
    var animated: Bool {
        self[PathPropertyKey.animated] as? Bool ?? true
    }

    internal var historicalLocation: Bool {
        self[PathPropertyKey.historicalLocation] as? Bool ?? false
    }

    var queryStringPresentation: Navigation.QueryStringPresentation {
        guard let rawValue = self[PathPropertyKey.queryStringPresentation] as? String,
              let presentation = Navigation.QueryStringPresentation(rawValue: rawValue) else {
            return .default
        }

        return presentation
    }
}
