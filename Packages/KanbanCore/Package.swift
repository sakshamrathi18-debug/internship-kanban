// swift-tools-version: 6.0
import PackageDescription

// Shared by the app and the widget extension: model, ordering, quick syntax,
// date labels, persistence (with backups and recovery) and the observable store.
let package = Package(
    name: "KanbanCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KanbanCore", targets: ["KanbanCore"]),
    ],
    targets: [
        .target(name: "KanbanCore"),
        .testTarget(name: "KanbanCoreTests", dependencies: ["KanbanCore"]),
    ]
)
