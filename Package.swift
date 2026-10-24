// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacSpacesWallpaperManager",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacSpacesWallpaperManager", targets: ["MacSpacesWallpaperManager"])],
    targets: [
        .target(name: "WallpaperCore"),
        .executableTarget(name: "MacSpacesWallpaperManager", dependencies: ["WallpaperCore"]),
        .testTarget(name: "WallpaperCoreTests", dependencies: ["WallpaperCore"])
    ]
)
