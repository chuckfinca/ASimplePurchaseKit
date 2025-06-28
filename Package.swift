// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ASimplePurchaseKit",
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
        .testTarget(
            name: "UnitTests",
            dependencies: ["ASimplePurchaseKit"],
            path: "Tests/UnitTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "ASimplePurchaseKit",
                "TestHostApp" // This makes TestHostApp the host
            ],
            path: "Tests/IntegrationTests",
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
