import Foundation

public enum EngineEventFixtures {
    public enum Scenario: String, CaseIterable {
        case coldBoot = "cold-boot"
        case ordinaryVisit = "ordinary-visit"
        case visitFailed = "visit-failed"
        case processDeath = "process-death"
        case refreshSuccess = "refresh-success"
        case refreshFailure = "refresh-failure"
        case revealedByPop = "revealed-by-pop"
    }

    public enum LoadError: Error {
        case missingResource(String)
    }

    public static func load(_ name: String) throws -> [EngineEvent] {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw LoadError.missingResource(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([EngineEvent].self, from: data)
    }

    public static func load(_ scenario: Scenario) throws -> [EngineEvent] {
        try load(scenario.rawValue)
    }
}
