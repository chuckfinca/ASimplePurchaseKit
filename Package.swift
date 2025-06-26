// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ASimplePurchaseKitProject",
    defaultLocalization: "en",
    platforms: [
        .iOS("16.4"),
        .macOS("13.3") // Keep if any part of your lib/tests is macOS compatible
    ],
    products: [
        .library(
            name: "ASimplePurchaseKit",
            targets: ["ASimplePurchaseKit"]
        ),
        // You might not need to export TestHostApp as a product
        // unless you intend for other packages to use it as an executable.
        // For local testing, just having it as a target is usually sufficient.
        // .executable(
        //     name: "TestHostApp",
        //     targets: ["TestHostApp"]
        // )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ASimplePurchaseKit",
            path: "Sources/ASimplePurchaseKit"
            // No need to list system framework dependencies like StoreKit here
        ),
        .executableTarget( // This is your app, used as a test host
            name: "TestHostApp",
            dependencies: ["ASimplePurchaseKit"],
            path: "Sources/TestHostApp", // Corresponds to your tree structure
            resources: [
                .process("Assets.xcassets") // For app icons, etc.
            ]
        ),
        .testTarget( // Unit tests for the library (no StoreKit interaction typically)
            name: "ASimplePurchaseKitTests",
            dependencies: ["ASimplePurchaseKit"],
            path: "Tests/ASimplePurchaseKitTests"
        ),
        .testTarget( // Integration tests, hosted by TestHostApp
            name: "PurchaseKitIntegrationTests",
            dependencies: [
                "ASimplePurchaseKit",
                "TestHostApp" // This makes TestHostApp the host
            ],
            path: "Tests/PurchaseKitIntegrationTests",
            resources: [
                .copy("Resources/Products.storekit"),
                .copy("Resources/TestLifetimeOnly.storekit"),
                .copy("Resources/TestMinimalSubscription.storekit"),
                .copy("Resources/TestSubscriptionOnly.storekit"),
                .copy("Resources/TestSubscriptionWithIntroOffer.storekit")
            ]
        )
    ]
)
