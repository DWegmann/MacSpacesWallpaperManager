import AppKit
import SwiftUI
import WallpaperCore

extension WallpaperColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var swiftUIColor: Color { Color(nsColor: nsColor) }

    var displayName: String {
        Self.namedColors.first { candidate in
            abs(red - candidate.color.red) < 0.0001 &&
            abs(green - candidate.color.green) < 0.0001 &&
            abs(blue - candidate.color.blue) < 0.0001
        }?.name ?? hexValue
    }

    private var hexValue: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()),
               Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    // Palette colors are converted to sRGB just like the persisted selection. Matching their
    // actual values also recovers names after a restart without storing extra configuration.
    private static let namedColors: [(name: String, color: WallpaperColor)] = {
        let palettes: [(String, [(String, String)])] = [
            ("Apple", [
                ("Black", "Schwarz"), ("White", "Weiß"), ("Red", "Rot"),
                ("Green", "Grün"), ("Blue", "Blau"), ("Cyan", "Cyan"),
                ("Magenta", "Magenta"), ("Yellow", "Gelb"), ("Orange", "Orange"),
                ("Purple", "Violett"), ("Brown", "Braun")
            ]),
            ("Crayons", [
                ("Licorice", "Lakritz"), ("Lead", "Blei"), ("Tungsten", "Wolfram"),
                ("Iron", "Eisen"), ("Steel", "Stahl"), ("Tin", "Zinn"),
                ("Nickel", "Nickel"), ("Aluminum", "Aluminium"), ("Magnesium", "Magnesium"),
                ("Silver", "Silber"), ("Mercury", "Quecksilber"), ("Snow", "Schnee"),
                ("Cayenne", "Cayenne"), ("Mocha", "Mokka"), ("Asparagus", "Spargel"),
                ("Fern", "Farn"), ("Clover", "Klee"), ("Moss", "Moos"),
                ("Teal", "Blaugrün"), ("Ocean", "Ozean"), ("Midnight", "Mitternacht"),
                ("Eggplant", "Aubergine"), ("Plum", "Pflaume"), ("Maroon", "Kastanie"),
                ("Maraschino", "Maraschino"), ("Tangerine", "Mandarine"), ("Lemon", "Zitrone"),
                ("Lime", "Limette"), ("Spring", "Frühling"), ("Sea Foam", "Meerschaum"),
                ("Turquoise", "Türkis"), ("Aqua", "Aqua"), ("Blueberry", "Blaubeere"),
                ("Grape", "Traube"), ("Magenta", "Magenta"), ("Strawberry", "Erdbeere"),
                ("Salmon", "Lachs"), ("Cantaloupe", "Melone"), ("Banana", "Banane"),
                ("Honeydew", "Honigmelone"), ("Flora", "Flora"), ("Spindrift", "Gischt"),
                ("Ice", "Eis"), ("Sky", "Himmel"), ("Orchid", "Orchidee"),
                ("Lavender", "Lavendel"), ("Bubblegum", "Kaugummi"), ("Carnation", "Nelke")
            ])
        ]
        var colors: [(name: String, color: WallpaperColor)] = [("Schwarz", .black)]
        for (palette, entries) in palettes {
            guard let list = NSColorList(named: palette) else { continue }
            for (key, name) in entries {
                guard let rgb = list.color(withKey: key)?.usingColorSpace(.sRGB) else { continue }
                colors.append((name, WallpaperColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                                                     blue: Double(rgb.blueComponent))))
            }
        }
        return colors
    }()

    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}
