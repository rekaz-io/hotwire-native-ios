import EngineInterface
import Foundation

public extension Navigator {
    struct Configuration {
        public let name: String
        public let startLocation: URL

        public let navigationPolicy: NavigationPolicy

        @MainActor
        public init(name: String,
                    startLocation: URL,
                    navigationPolicy: NavigationPolicy? = nil) {
            self.name = name
            self.startLocation = startLocation
            self.navigationPolicy = navigationPolicy ?? DefaultNavigationPolicy()
        }
    }
}
