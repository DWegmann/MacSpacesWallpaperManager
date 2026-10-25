// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacSpacesWallpaperManager",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacSpacesWallpaperManager", targets: ["MacSpacesWallpaperManager"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "WallpaperCore"),
        .executableTarget(
            name: "MacSpacesWallpaperManager",
            dependencies: ["WallpaperCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "WallpaperCoreTests", dependencies: ["WallpaperCore"])
    ]
)
