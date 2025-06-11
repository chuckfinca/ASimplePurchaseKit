# ASimplePurchaseKit

A lightweight, modern, and testable Swift package for handling in-app purchases using StoreKit 2. Designed with SwiftUI in mind, ASimplePurchaseKit simplifies fetching products, making purchases, and checking entitlement status with a clean, async/await-based API.

## ✨ Features

- **Modern API**: Built exclusively on the new StoreKit 2 async/await APIs.
- **SwiftUI Ready**: The main PurchaseService is an ObservableObject, making it trivial to bind your UI to purchase states.
- **Highly Testable**: Built with protocols and dependency injection, allowing you to easily mock the purchase flow in your unit tests.
- **Automatic Transaction Handling**: Listens for Transaction.updates to automatically handle renewals, refunds, and purchases made outside the app.
- **Simple Entitlement Checking**: A clear EntitlementStatus enum (.subscribed, .notSubscribed) serves as the single source of truth for user access.
- **Handles Subscriptions and One-Time Purchases**: Supports auto-renewable subscriptions, non-renewing subscriptions, and non-consumable products.
- **Zero External Dependencies**: Pure Swift and StoreKit.

## 📋 Requirements

- iOS 16.0+
- macOS 12.0+

## 📦 Installation

You can add ASimplePurchaseKit to your Xcode project using the Swift Package Manager.

1. In Xcode, open your project and navigate to **File > Add Packages...**
2. Paste the repository URL into the search bar:
   ```
   https://github.com/chuckfinca/ASimplePurchaseKit.git
   ```
3. Select the ASimplePurchaseKit package and add it to your app target.

*(Replace with your actual GitHub repository URL)*

## 🚀 Usage

### 1. Configure the Service

First, you'll need a `.storekit` configuration file in your project for testing. Define your product identifiers there and in App Store Connect.

In your app's entry point or a central location, initialize the PurchaseService. It's an ObservableObject, so you can inject it into your SwiftUI environment.

```swift
import SwiftUI
import ASimplePurchaseKit

@main
struct YourApp: App {
    // Create the config with your product IDs
    private static let purchaseConfig = PurchaseConfig(
        productIDs: ["com.yourapp.pro.monthly", "com.yourapp.pro.yearly"]
    )
    
    // Initialize the service and hold it in a @StateObject
    @StateObject private var purchaseService = PurchaseService(config: purchaseConfig)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseService) // Make it available to all views
        }
    }
}
```

### 2. Display Products and Make a Purchase

In your paywall view, access the service from the environment and display the fetched products.

```swift
import SwiftUI
import ASimplePurchaseKit
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var purchaseService: PurchaseService
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Go Pro!")
                .font(.largeTitle)

            // Loop through the available products
            ForEach(purchaseService.availableProducts) { product in
                Button(action: {
                    Task {
                        // The purchase function is async
                        await purchaseService.purchase(product)
                    }
                }) {
                    ProductView(product: product)
                }
            }
            
            // Show a progress indicator while purchasing
            if purchaseService.isPurchasing {
                ProgressView()
            }
            
            // Optionally, display errors
            if let error = purchaseService.lastError {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

// A simple view to display a product
struct ProductView: View {
    let product: Product
    
    var body: some View {
        VStack {
            Text(product.displayName)
                .font(.headline)
            Text(product.displayPrice)
                .font(.subheadline)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}
```

### 3. Check Entitlement Status

Use the `entitlementStatus` property to control access to premium features. The `.isActive` property is a convenient shortcut.

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var purchaseService: PurchaseService

    var body: some View {
        if purchaseService.entitlementStatus.isActive {
            // Show premium content if the user is subscribed
            PremiumFeaturesView()
        } else {
            // Otherwise, show the paywall
            PaywallView()
        }
    }
}
```

### 4. Restore Purchases

Provide a button for users to restore their previous purchases. ASimplePurchaseKit will sync with the App Store, and the transaction listener will automatically update the entitlement status.

```swift
Button("Restore Purchases") {
    Task {
        await purchaseService.restorePurchases()
    }
}
```

## 🧪 Testing

The library is designed to be easily testable. You can initialize PurchaseService with a MockPurchaseProvider to simulate any StoreKit scenario without needing the network.

```swift
import XCTest
@testable import ASimplePurchaseKit // Use @testable to access internal types

@MainActor
final class MyViewModelTests: XCTestCase {

    var sut: PurchaseService!
    var mockProvider: MockPurchaseProvider!

    override func setUp() {
        super.setUp()
        mockProvider = MockPurchaseProvider()
        
        // Initialize the SUT with the mock provider
        sut = PurchaseService(
            productIDs: ["com.test.product"],
            productProvider: mockProvider,
            purchaser: mockProvider,
            receiptValidator: mockProvider
        )
    }

    func test_purchase_succeeds_and_updates_entitlement() async {
        // ARRANGE: Configure the mock to return a successful transaction
        // and a "subscribed" status.
        let mockTransaction = // ... create a mock Transaction if needed for your test
        mockProvider.purchaseResult = .success(mockTransaction)
        mockProvider.entitlementResult = .success(.subscribed(expires: nil, isInGracePeriod: false))
        
        let mockProduct = // ... create a mock Product
        
        // ACT
        await sut.purchase(mockProduct)
        
        // ASSERT
        XCTAssertTrue(sut.entitlementStatus.isActive, "User should be entitled after a successful purchase")
        XCTAssertNil(sut.lastError)
        XCTAssertEqual(mockProvider.purchaseCallCount, 1)
    }
}
```

## 🏗️ Architecture

- **PurchaseService**: The main public class and ObservableObject that your app interacts with.
- **PurchaseConfig**: A simple struct to configure the service with your product IDs.
- **EntitlementStatus**: A public enum that represents the user's access level.
- **PurchaseError**: A public enum for specific, user-facing errors.
- **PurchaseProtocols**: A set of protocols (ProductProvider, Purchaser, ReceiptValidator) that define the core purchase-related actions.
- **LivePurchaseProvider**: The internal, concrete implementation of the protocols that communicates with StoreKit. Your app never touches this directly.

## License

This project is licensed under the MIT License. See the LICENSE file for details.