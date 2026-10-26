import Foundation

public struct ConfigurationStore {
    public let url: URL

    public init(url: URL? = nil) {
        // Preserve the existing data location across the rename so saved Space rules remain available.
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpacePaper", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppConfiguration() }
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: url))
        guard configuration.schemaVersion == 1 else { throw ConfigurationError.unsupportedVersion }
        return configuration
    }

    public func save(_ configuration: AppConfiguration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}

public enum ConfigurationError: LocalizedError {
    case unsupportedVersion
    public var errorDescription: String? { "These settings were created by a newer version of Mac Spaces Wallpaper Manager." }
}
