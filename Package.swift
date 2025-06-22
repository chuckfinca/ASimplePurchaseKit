// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ASimplePurchaseKitProject", // The name for the entire SPM package
    defaultLocalization: "en",         // Optional: if you have localizations
    platforms: [
        .iOS(.v16),
        .macOS(.v12) // If your library or tests also run on macOS
    ],
    products: [
        // Product 1: The ASimplePurchaseKit library
        .library(
            name: "ASimplePurchaseKit",
            targets: ["ASimplePurchaseKit"]
        ),
        // Product 2: The TestHostApp executable (useful for running/testing)
        .executable(
            name: "TestHostApp",
            targets: ["TestHostApp"]
        )
    ],
    dependencies: [
        // List any external package dependencies here if ASimplePurchaseKit had them
        // For now, it seems to have none.
    ],
    targets: [
        // Target 1: ASimplePurchaseKit library sources
        .target(
            name: "ASimplePurchaseKit",
            dependencies: [], // No external dependencies for the library itself
            path: "Sources/ASimplePurchaseKit"
            // If ASimplePurchaseKit itself had resources, define them here
        ),

        // Target 2: Unit tests for ASimplePurchaseKit
        .testTarget(
            name: "ASimplePurchaseKitTests",
            dependencies: ["ASimplePurchaseKit"],
            path: "Tests/ASimplePurchaseKitTests"
            // If these unit tests have specific resources, define them here
        ),

        // Target 3: TestHostApp application sources
        .executableTarget(
            name: "TestHostApp",
            dependencies: [
                "ASimplePurchaseKit" // The app will use your library
            ],
            path: "Sources/TestHostApp",
            resources: [
                // Process the Assets.xcassets for app icons, colors, etc.
                .process("Assets.xcassets")
            ]
            // SPM and Xcode handle basic Info.plist generation for executable targets.
            // For custom Info.plist values, you often configure them in Xcode's
            // build settings for the target after opening the package.
        ),

        // Target 4: Integration tests
        .testTarget(
            name: "PurchaseKitIntegrationTests",
            dependencies: [
                "TestHostApp",        // This makes TestHostApp the "host" for these tests
                "ASimplePurchaseKit"  // Tests will also directly use the library
            ],
            path: "Tests/PurchaseKitIntegrationTests",
            resources: [
                // Make .storekit files available to the test bundle
                .copy("Resources/Products.storekit"),
                .copy("Resources/TestLifetimeOnly.storekit"),
                .copy("Resources/TestMinimalSubscription.storekit"),
                .copy("Resources/TestSubscriptionOnly.storekit")
                // Add any other .storekit files here if you have more
            ]
        )
    ]
)