// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ASimplePurchaseKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ASimplePurchaseKit",
            targets: ["ASimplePurchaseKit"]),
    ],
    dependencies: [
        // No external dependencies!
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ASimplePurchaseKit",
            dependencies: [] // Pure Swift and StoreKit
        ),
        .testTarget(
            name: "ASimplePurchaseKitTests",
            dependencies: ["ASimplePurchaseKit"],
            resources: [
                // This makes the .storekit file available to your tests
                .copy("Products.storekit")
            ]
        ),
    ]
)
