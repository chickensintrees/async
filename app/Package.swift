// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Async",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Async", targets: ["Async"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Async",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/Async"
        ),
        .testTarget(
            name: "AsyncTests",
            dependencies: ["Async"],
            path: "Tests/AsyncTests"
        )
    ]
)
