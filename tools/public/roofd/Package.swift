// swift-tools-version:6.0
// roofd — a session manager for terminal coding agents (public copy of One Roof's runtime).
// Build: scripts/build-roofvt.sh once, then swift build && swift test.
import PackageDescription

let package = Package(
    name: "roofd",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "roofd", targets: ["roofd"])],
    targets: [
        // Ghostty's VT core as a headless terminal per session (Zig shim, built by scripts/build-roofvt.sh).
        .binaryTarget(name: "RoofVT", path: "Vendor/RoofVT.xcframework"),
        // fork/setsid/TIOCSCTTY/execve: the part Swift must not do itself.
        .target(name: "CRoofSpawn"),
        // The library roofd shares with the One Roof app: status engine, agent kinds, process probe, session store.
        .target(
            name: "OneRoofCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The session manager: daemon, per-session holders, attach client.
        .executableTarget(
            name: "roofd",
            dependencies: ["RoofVT", "CRoofSpawn", "OneRoofCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        // Framing, idempotent create, redraw-before-output ordering, memory, against a real daemon in a temp folder.
        .testTarget(
            name: "RoofdTests",
            dependencies: ["roofd"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
