// swift-tools-version: 6.0
import PackageDescription

// macOS 15 is the floor, not 14. D3DMetal itself declares `minos 14.0`, but SwiftUI's
// UtilityWindow is `@available(macOS 15.0, *)` and the Game Porting Toolkit that supplies
// D3DMetal wanted Sequoia anyway. See docs/layout.md.
let package = Package(
    name: "sake",
    platforms: [.macOS(.v15)],
    targets: [
        // Everything that is not a view, so it can be tested without a window. The app
        // target stays thin.
        .target(name: "SakeKit"),
        .executableTarget(name: "sake", dependencies: ["SakeKit"]),
        .testTarget(name: "SakeKitTests", dependencies: ["SakeKit"]),
    ]
)
