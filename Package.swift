// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ASimplePurchaseKitProject",
    defaultLocalization: "en",
    platforms: [
        .iOS("16.4"),
        .macOS("13.3")
    ],
    products: [
        .library(
            name: "ASimplePurchaseKit",
            targets: ["ASimplePurchaseKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ASimplePurchaseKit",
            path: "Sources/ASimplePurchaseKit"
        ),
        .executableTarget(
            name: "TestHostApp",
            dependencies: ["ASimplePurchaseKit"],
            path: "Sources/TestHostApp",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget( // For unit tests
            name: "ASimplePurchaseKitTests",
            dependencies: ["ASimplePurchaseKit"],
            path: "Tests/ASimplePurchaseKitTests"
        ),
        .testTarget( // For integration tests, hosted by TestHostApp
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
