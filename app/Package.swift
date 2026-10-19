// swift-tools-version:6.0
// One Roof — native Mac command center for the agent fleet.
// Build: scripts/build-ghosttykit.sh once, then scripts/bundle.sh → build/One Roof.app
import PackageDescription
import Foundation

// CI has no libghostty build (Vendor/ is gitignored, 135 MB): there only OneRoofCore and its tests build.
let hasGhostty = FileManager.default.fileExists(atPath: Context.packageDirectory + "/Vendor/GhosttyKit.xcframework")

let package = Package(
    name: "OneRoof",
    platforms: [.macOS(.v14)],
    products: hasGhostty ? [.executable(name: "OneRoof", targets: ["OneRoof"])] : [],
    targets: (hasGhostty ? appTargets : []) + [
        // Pure Swift: sessions, herdr client, account probe, store, grouping, themes. Unit-tested.
        .target(
            name: "OneRoofCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        .testTarget(
            name: "OneRoofCoreTests",
            dependencies: ["OneRoofCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

var appTargets: [Target] {
    [
        // libghostty, built from Ghostty v1.3.1 by scripts/build-ghosttykit.sh (MIT).
        .binaryTarget(name: "GhosttyKit", path: "Vendor/GhosttyKit.xcframework"),

        // The app: window, three panels, libghostty terminal surfaces.
        .executableTarget(
            name: "OneRoof",
            dependencies: ["OneRoofCore", "GhosttyKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
}
