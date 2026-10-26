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
                ("Black", "Black"), ("White", "White"), ("Red", "Red"),
                ("Green", "Green"), ("Blue", "Blue"), ("Cyan", "Cyan"),
                ("Magenta", "Magenta"), ("Yellow", "Yellow"), ("Orange", "Orange"),
                ("Purple", "Purple"), ("Brown", "Brown")
            ]),
            ("Crayons", [
                ("Licorice", "Licorice"), ("Lead", "Lead"), ("Tungsten", "Tungsten"),
                ("Iron", "Iron"), ("Steel", "Steel"), ("Tin", "Tin"),
                ("Nickel", "Nickel"), ("Aluminum", "Aluminum"), ("Magnesium", "Magnesium"),
                ("Silver", "Silver"), ("Mercury", "Mercury"), ("Snow", "Snow"),
                ("Cayenne", "Cayenne"), ("Mocha", "Mocha"), ("Asparagus", "Asparagus"),
                ("Fern", "Fern"), ("Clover", "Clover"), ("Moss", "Moss"),
                ("Teal", "Teal"), ("Ocean", "Ocean"), ("Midnight", "Midnight"),
                ("Eggplant", "Eggplant"), ("Plum", "Plum"), ("Maroon", "Maroon"),
                ("Maraschino", "Maraschino"), ("Tangerine", "Tangerine"), ("Lemon", "Lemon"),
                ("Lime", "Lime"), ("Spring", "Spring"), ("Sea Foam", "Sea Foam"),
                ("Turquoise", "Turquoise"), ("Aqua", "Aqua"), ("Blueberry", "Blueberry"),
                ("Grape", "Grape"), ("Magenta", "Magenta"), ("Strawberry", "Strawberry"),
                ("Salmon", "Salmon"), ("Cantaloupe", "Cantaloupe"), ("Banana", "Banana"),
                ("Honeydew", "Honeydew"), ("Flora", "Flora"), ("Spindrift", "Spindrift"),
                ("Ice", "Ice"), ("Sky", "Sky"), ("Orchid", "Orchid"),
                ("Lavender", "Lavender"), ("Bubblegum", "Bubblegum"), ("Carnation", "Carnation")
            ])
        ]
        var colors: [(name: String, color: WallpaperColor)] = [("Black", .black)]
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
