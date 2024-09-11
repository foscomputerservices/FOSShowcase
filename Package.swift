// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FOSShowcase",
    platforms: [
        .macOS(.v14)
        // .linux()
    ],
    products: [
        .library(
            name: "ViewModels",
            targets: ["ViewModels"]
        ),
        .executable(
            name: "VaporWebServer",
            targets: ["WebServer"]
        ),
        .executable(
            name: "VaporLeafWebApp",
            targets: ["VaporLeafWebApp"]
        )
    ],
    dependencies: [
        // 🍎 frameworks
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        // .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),

        // FOS frameworks
        // .package(url: "https://github.com/foscomputerservices/FOSUtilities.git", branch: "main"),
        .package(path: "../FOSUtilities"),

        // Third 🥳 frameworks
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.102.0")),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.4.0"),
        .package(url: "https://github.com/twostraws/Ignite.git", branch: "main"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.0")
    ],
    targets: [
        .target(
            name: "ViewModels",
            dependencies: [
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .executableTarget(
            name: "WebServer",
            dependencies: [
                .byName(name: "ViewModels"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ],
            resources: [
                .copy("../Resources")
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .executableTarget(
            name: "IgniteWebApp",
            dependencies: [
                .byName(name: "ViewModels"),
                .byName(name: "Ignite"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ],
            exclude: [
                "Build", "Includes/Includes.txt", "Content/Content.txt"
            ],
            resources: [
                .copy("../Resources")
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .executableTarget(
            name: "VaporLeafWebApp",
            dependencies: [
                .byName(name: "ViewModels"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "Vapor", package: "Vapor"),
                .product(name: "Leaf", package: "leaf")
            ],
            resources: [
                .copy("Views")
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .testTarget(
            name: "ViewModelTests",
            dependencies: [
                .target(name: "ViewModels"),
                .product(name: "Vapor", package: "Vapor"),
                .product(name: "Testing", package: "swift-testing"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSTesting", package: "FOSUtilities")
            ],
            resources: [
                .copy("../../Sources/Resources")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "WebServerTests",
            dependencies: [
                .target(name: "WebServer"),
                .product(name: "Vapor", package: "Vapor"),
                .product(name: "Testing", package: "swift-testing")
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
] }

#if os(macOS)
let plugins: [PackageDescription.Target.PluginUsage]? = [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
]
#else
let plugins: [PackageDescription.Target.PluginUsage]? = nil
#endif
