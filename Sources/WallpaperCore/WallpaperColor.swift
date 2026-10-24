import Foundation

/// Opaque sRGB color, independent of AppKit/SwiftUI and safe to persist with a Space rule.
public struct WallpaperColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public static let black = WallpaperColor(red: 0, green: 0, blue: 0)

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.component(red)
        self.green = Self.component(green)
        self.blue = Self.component(blue)
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(red: try values.decode(Double.self, forKey: .red),
                  green: try values.decode(Double.self, forKey: .green),
                  blue: try values.decode(Double.self, forKey: .blue))
    }

    private static func component(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
