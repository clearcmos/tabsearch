// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tabsearch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tabsearch", targets: ["tabsearch"]),
        .executable(name: "TabSearchBar", targets: ["TabSearchBar"]),
    ],
    targets: [
        // Shared core: drives Terminal.app via AppleScript. No UI dependencies, so both the
        // CLI and the menu bar app import it unchanged.
        .target(name: "TabSearchKit"),
        .executableTarget(
            name: "tabsearch",
            dependencies: ["TabSearchKit"]
        ),
        // Menu bar app: global Shift+Cmd+F hotkey + floating search panel.
        .executableTarget(
            name: "TabSearchBar",
            dependencies: ["TabSearchKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
